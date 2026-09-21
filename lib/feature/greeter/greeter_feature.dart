import 'dart:async';

import 'package:flutter/foundation.dart';

import 'greeter_commands.dart';
import 'greeter_effect.dart';
import 'greeter_slots.dart';
import 'greeter_state.dart';
import 'ports/greeter_gateway.dart';
import 'ports/session_store.dart';

/// Session id or name fragments preferred when the user has no stored choice.
const _preferredSessionNames = ['hyprland', 'sway'];

/// Application-facing state owner for the greeter flow.
///
/// This is deliberately independent from Scene widgets. D-Bus is represented
/// by [GreeterGateway] and never accessed directly from this class.
class GreeterFeature {
  // The public parameter names cannot use the library-private field names.
  GreeterFeature({
    required GreeterGateway gateway,
    SessionStore sessionStore = const NoopSessionStore(),
  }) : _gateway = gateway, // ignore: prefer_initializing_formals
       _sessionStore = sessionStore; // ignore: prefer_initializing_formals

  final GreeterGateway _gateway;
  final SessionStore _sessionStore;
  final StreamController<FeatureEffect> _effects =
      StreamController<FeatureEffect>.broadcast();
  StreamSubscription<GreeterEvent>? _eventSubscription;
  final List<GreeterEvent> _eventsDuringBegin = <GreeterEvent>[];
  final ValueNotifier<ServiceSlots> _serviceSlots = ValueNotifier(const (
    mode: ServiceMode.starting,
    error: null,
  ));
  final ValueNotifier<AuthPromptSlots> _authPromptSlots = ValueNotifier((
    mode: AuthMode.userSelection,
    selectedUser: null,
    prompt: null,
    error: null,
    promptError: null,
  ));
  final ValueNotifier<AccountPickerSlots> _accountPickerSlots = ValueNotifier(
    AccountPickerSlots(users: const [], selected: null),
  );
  final ValueNotifier<SessionPickerSlots> _sessionPickerSlots = ValueNotifier(
    SessionPickerSlots(
      mode: CatalogMode.empty,
      sessions: const [],
      selected: null,
      error: null,
    ),
  );
  final ValueNotifier<PowerSlots> _powerSlots = ValueNotifier(const (
    mode: PowerMode.idle,
    error: null,
  ));
  final ValueNotifier<bool> _dormantSlots = ValueNotifier(true);
  GreeterState _state = GreeterState.initial();
  String? _attemptId;
  bool _initialized = false;
  bool _beginInFlight = false;
  bool _sessionStartInFlight = false;
  bool _disposed = false;
  int _sessionLoadGeneration = 0;

  GreeterState get state => _state;

  GreeterSceneSlots get slots => GreeterSceneSlots.fromState(_state);

  ValueListenable<ServiceSlots> get serviceSlots => _serviceSlots;

  ValueListenable<AuthPromptSlots> get authPromptSlots => _authPromptSlots;

  ValueListenable<AccountPickerSlots> get accountPickerSlots =>
      _accountPickerSlots;

  ValueListenable<SessionPickerSlots> get sessionPickerSlots =>
      _sessionPickerSlots;

  ValueListenable<PowerSlots> get powerSlots => _powerSlots;

  ValueListenable<bool> get dormantSlots => _dormantSlots;

  Stream<FeatureEffect> get effects => _effects.stream;

  Future<void> dispatch(GreeterCommand command) async {
    switch (command) {
      case SelectUserCommand(:final user):
        _selectUser(user);
      case BeginAuthenticationCommand():
        await _beginAuthentication();
      case RespondToPromptCommand(:final response):
        await _respondToPrompt(response);
      case CancelAuthenticationCommand():
        await _cancelAuthentication();
      case SelectSessionCommand(:final session):
        _selectSession(session);
      case StartSelectedSessionCommand():
        await _startSelectedSession();
      case RequestPowerActionCommand(:final action):
        await _requestPowerAction(action);
      case RetryAuthenticationCommand():
        _retryAuthentication();
      case RetryPromptCommand():
        _retryPrompt();
      case ReconnectServiceCommand():
        await _reconnectService();
      case RetrySessionCatalogCommand():
        await _retrySessionCatalog();
      case WakeGreeterCommand():
        _wakeGreeter();
      case SleepGreeterCommand():
        _sleepGreeter();
    }
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _eventSubscription = _gateway.events.listen(_handleEvent);
    await _loadService();
  }

  Future<void> _loadService() async {
    _replace(_state.copyWith(serviceMode: ServiceMode.starting));
    try {
      final snapshot = await _gateway.getState();
      final users = await _gateway.listUsers();
      if (snapshot.state != BackendAuthState.idle) {
        _replace(
          _state.copyWith(
            serviceMode: ServiceMode.ready,
            users: users,
            authMode: AuthMode.error,
            backendAuthState: snapshot.state,
            authError: (
              kind: GreeterErrorKind.authentication,
              message: snapshot.detail.isEmpty
                  ? 'The greeter service has an active authentication transaction.'
                  : snapshot.detail,
              recovery: GreeterRecovery.reconnectService,
            ),
            clearPromptError: true,
            dormant: false,
            clearServiceError: true,
          ),
        );
        return;
      }
      _replace(
        _state.copyWith(
          serviceMode: ServiceMode.ready,
          users: users,
          selectedUser: users.length == 1 ? users.first : null,
          authMode: AuthMode.userSelection,
          backendAuthState: snapshot.state,
          catalogMode: CatalogMode.loading,
          sessions: const [],
          clearSelectedSession: true,
          clearServiceError: true,
          clearAuthError: true,
          clearPromptError: true,
        ),
      );
      unawaited(_loadSessionCatalog());
    } on Object catch (error) {
      _replace(
        _state.copyWith(
          serviceMode: ServiceMode.unavailable,
          authMode: AuthMode.error,
          dormant: false,
          serviceError: _getGreeterError(
            error,
            fallbackKind: GreeterErrorKind.transport,
            recovery: GreeterRecovery.reconnectService,
          ),
        ),
      );
    }
  }

  Future<void> _reconnectService() async {
    if (_state.serviceMode == ServiceMode.starting) {
      return;
    }
    _attemptId = null;
    _eventsDuringBegin.clear();
    _sessionLoadGeneration++;
    _replace(
      _state.copyWith(
        serviceMode: ServiceMode.starting,
        authMode: AuthMode.userSelection,
        clearServiceError: true,
        clearAuthError: true,
        clearCatalogError: true,
        catalogMode: CatalogMode.empty,
        sessions: const [],
        clearSelectedUser: true,
        clearSelectedSession: true,
        clearPrompt: true,
        clearPromptError: true,
        backendAuthState: BackendAuthState.idle,
      ),
    );
    await _loadService();
  }

  void _wakeGreeter() {
    if (!_state.dormant || _state.serviceMode != ServiceMode.ready) {
      return;
    }
    _replace(
      _state.copyWith(
        dormant: false,
        clearAuthError: true,
        clearPromptError: true,
      ),
    );
    _beginAuthenticationIfReady();
  }

  void _sleepGreeter() {
    if (_state.dormant || _state.authMode == AuthMode.handingOff) {
      return;
    }
    final attemptId = _attemptId;
    _attemptId = null;
    _eventsDuringBegin.clear();
    _replace(
      _state.copyWith(
        dormant: true,
        authMode: AuthMode.userSelection,
        clearPrompt: true,
        clearAuthError: true,
        clearPromptError: true,
        clearCatalogError: true,
        backendAuthState: BackendAuthState.idle,
      ),
    );
    if (attemptId != null) {
      unawaited(_cancelAttempt(attemptId));
    }
  }

  Future<void> _cancelAttempt(String attemptId) async {
    try {
      await _gateway.cancel(attemptId);
    } on Object {
      // Sleeping is best effort: the greeter returns to the background even
      // when the backend cannot cancel the abandoned attempt.
    }
  }

  void _selectUser(UserSummary user) {
    if (_state.serviceMode != ServiceMode.ready ||
        !_state.users.any((candidate) => candidate.id == user.id)) {
      return;
    }
    _replace(
      _state.copyWith(
        selectedUser: user,
        clearAuthError: true,
        clearPromptError: true,
      ),
    );
    _beginAuthenticationIfReady();
  }

  /// Starts the backend conversation as soon as an account and session are
  /// both known, so the credential field is usable without a confirm step.
  void _beginAuthenticationIfReady() {
    if (_state.dormant ||
        _state.authMode != AuthMode.userSelection ||
        _state.selectedUser == null ||
        _state.selectedSession == null) {
      return;
    }
    unawaited(_beginAuthentication());
  }

  Future<void> _beginAuthentication() async {
    final user = _state.selectedUser;
    if (user == null ||
        _state.selectedSession == null ||
        _state.authMode != AuthMode.userSelection) {
      return;
    }

    _replace(
      _state.copyWith(
        authMode: AuthMode.submitting,
        clearAuthError: true,
        clearPromptError: true,
      ),
    );

    _beginInFlight = true;
    _eventsDuringBegin.clear();
    try {
      final attemptId = await _gateway.beginAuthentication(user.id);
      _attemptId = attemptId;
      final pendingEvents = List<GreeterEvent>.from(_eventsDuringBegin);
      _eventsDuringBegin.clear();
      _beginInFlight = false;
      for (final event in pendingEvents) {
        _handleEvent(event);
      }
    } on Object catch (error) {
      _eventsDuringBegin.clear();
      _beginInFlight = false;
      _showAuthError(
        _getGreeterError(
          error,
          fallbackKind: GreeterErrorKind.authentication,
          recovery: GreeterRecovery.retryAuthentication,
        ),
      );
    }
  }

  Future<void> _respondToPrompt(String response) async {
    final attemptId = _attemptId;
    if (attemptId == null || _state.authMode != AuthMode.prompting) {
      return;
    }
    if (response.trim().isEmpty) {
      _showAuthError(const (
        kind: GreeterErrorKind.input,
        message: 'A response is required.',
        recovery: GreeterRecovery.retryPrompt,
      ));
      return;
    }

    _replace(
      _state.copyWith(
        authMode: AuthMode.submitting,
        clearAuthError: true,
        clearPromptError: true,
      ),
    );
    try {
      await _gateway.respond(attemptId, response);
    } on Object catch (error) {
      if (attemptId == _attemptId) {
        _showAuthError(
          _getGreeterError(
            error,
            fallbackKind: GreeterErrorKind.authentication,
            recovery: GreeterRecovery.retryAuthentication,
          ),
        );
      }
    }
  }

  Future<void> _cancelAuthentication() async {
    final attemptId = _attemptId;
    if (attemptId == null) {
      _resetToUserSelection(clearSelectedUser: true);
      return;
    }

    _attemptId = null;
    try {
      await _gateway.cancel(attemptId);
    } on Object catch (error) {
      _replace(
        _state.copyWith(
          serviceMode: ServiceMode.unavailable,
          authMode: AuthMode.error,
          dormant: false,
          serviceError: _getGreeterError(
            error,
            fallbackKind: GreeterErrorKind.transport,
            recovery: GreeterRecovery.reconnectService,
          ),
          clearAuthError: true,
          clearPromptError: true,
        ),
      );
      return;
    }
    _resetToUserSelection(clearSelectedUser: true);
  }

  void _selectSession(SessionSummary session) {
    if (_state.serviceMode != ServiceMode.ready ||
        _state.catalogMode != CatalogMode.ready ||
        !_state.sessions.any((candidate) => candidate.id == session.id)) {
      return;
    }
    _replace(
      _state.copyWith(
        selectedSession: session,
        clearCatalogError: true,
        clearAuthError: true,
        clearPromptError: true,
      ),
    );
    unawaited(_sessionStore.saveSelectedSessionId(session.id));
    _beginAuthenticationIfReady();
  }

  Future<void> _startSelectedSession() async {
    final attemptId = _attemptId;
    final session = _state.selectedSession;
    if (attemptId == null || session == null || _sessionStartInFlight) {
      return;
    }

    _sessionStartInFlight = true;
    _replace(
      _state.copyWith(authMode: AuthMode.submitting, clearCatalogError: true),
    );
    try {
      await _gateway.startSession(attemptId, session.id);
      _replace(
        _state.copyWith(
          authMode: AuthMode.handingOff,
          clearAuthError: true,
          clearCatalogError: true,
        ),
      );
      _effects.add(const ExitAfterHandoffEffect());
    } on Object catch (error) {
      _showSessionError(
        _getGreeterError(
          error,
          fallbackKind: GreeterErrorKind.session,
          recovery: GreeterRecovery.selectSession,
        ),
      );
    } finally {
      _sessionStartInFlight = false;
    }
  }

  Future<void> _requestPowerAction(PowerAction action) async {
    if (_state.powerMode == PowerMode.executing) {
      return;
    }
    _replace(
      _state.copyWith(powerMode: PowerMode.executing, clearPowerError: true),
    );
    try {
      await _gateway.powerAction(action);
      _replace(_state.copyWith(powerMode: PowerMode.succeeded));
    } on Object catch (error) {
      final powerError = _getGreeterError(
        error,
        fallbackKind: GreeterErrorKind.power,
        recovery: GreeterRecovery.selectUser,
      );
      _replace(
        _state.copyWith(powerMode: PowerMode.failed, powerError: powerError),
      );
      _effects.add(ShowNoticeEffect(powerError.message, isError: true));
    }
  }

  void _retryAuthentication() {
    _attemptId = null;
    _replace(
      _state.copyWith(
        serviceMode: ServiceMode.ready,
        authMode: AuthMode.userSelection,
        clearPrompt: true,
        clearAuthError: true,
        clearPromptError: true,
        clearCatalogError: _state.sessions.isNotEmpty,
        catalogMode: _state.sessions.isNotEmpty
            ? CatalogMode.ready
            : _state.catalogMode,
        backendAuthState: BackendAuthState.idle,
      ),
    );
    _beginAuthenticationIfReady();
  }

  void _retryPrompt() {
    if (_attemptId == null || _state.prompt == null) {
      _retryAuthentication();
      return;
    }
    _replace(
      _state.copyWith(
        authMode: AuthMode.prompting,
        clearAuthError: true,
        clearPromptError: true,
      ),
    );
    _effects.add(const RequestFocusEffect('credential'));
  }

  Future<void> _retrySessionCatalog() async {
    if (_state.serviceMode != ServiceMode.ready) {
      return;
    }
    await _loadSessionCatalog();
  }

  void _handleEvent(GreeterEvent event) {
    switch (event) {
      case BackendDisconnected():
        _attemptId = null;
        _replace(
          _state.copyWith(
            serviceMode: ServiceMode.unavailable,
            authMode: AuthMode.error,
            dormant: false,
            serviceError: const (
              kind: GreeterErrorKind.transport,
              message: 'The greeter service is unavailable.',
              recovery: GreeterRecovery.reconnectService,
            ),
          ),
        );
      case BackendStateChanged(:final attemptId, :final state, :final detail):
        if (_queueEventDuringBegin(event) || attemptId != _attemptId) {
          return;
        }
        _applyBackendState(state, detail);
      case BackendPromptReceived(:final attemptId, :final kind, :final text):
        if (_queueEventDuringBegin(event) || attemptId != _attemptId) {
          return;
        }
        if (kind == PromptKind.visible || kind == PromptKind.secret) {
          _replace(
            _state.copyWith(
              authMode: AuthMode.prompting,
              prompt: (kind: kind, text: text),
              backendAuthState: BackendAuthState.waitingForInput,
              clearAuthError: true,
            ),
          );
          _effects.add(const RequestFocusEffect('credential'));
        } else if (kind == PromptKind.error) {
          _replace(_state.copyWith(promptError: text));
        } else {
          _effects.add(ShowNoticeEffect(text));
        }
    }
  }

  bool _queueEventDuringBegin(GreeterEvent event) {
    if (_attemptId != null || !_beginInFlight) {
      return false;
    }
    _eventsDuringBegin.add(event);
    return true;
  }

  void _applyBackendState(BackendAuthState state, String detail) {
    final nextMode = switch (state) {
      BackendAuthState.creatingSession ||
      BackendAuthState.promptPending ||
      BackendAuthState.submittingResponse ||
      BackendAuthState.resolvingSession ||
      BackendAuthState.startingSession => AuthMode.submitting,
      BackendAuthState.authenticated => AuthMode.submitting,
      BackendAuthState.handingOff => AuthMode.handingOff,
      BackendAuthState.failed => AuthMode.error,
      BackendAuthState.cancelling => AuthMode.submitting,
      BackendAuthState.idle => AuthMode.userSelection,
      BackendAuthState.waitingForInput => _state.authMode,
      BackendAuthState.unknown => _state.authMode,
    };

    _replace(
      _state.copyWith(
        authMode: nextMode,
        backendAuthState: state,
        authError: state == BackendAuthState.failed
            ? (
                kind: GreeterErrorKind.authentication,
                message: detail,
                recovery: GreeterRecovery.retryAuthentication,
              )
            : null,
        clearAuthError: state != BackendAuthState.failed,
        clearPromptError:
            state == BackendAuthState.authenticated ||
            state == BackendAuthState.failed,
        clearPrompt:
            state == BackendAuthState.authenticated ||
            state == BackendAuthState.failed,
      ),
    );
    if (state == BackendAuthState.authenticated) {
      if (_state.selectedSession == null) {
        _replace(
          _state.copyWith(
            authMode: AuthMode.sessionSelection,
            clearAuthError: true,
          ),
        );
      } else {
        unawaited(_startSelectedSession());
      }
    }
    if (state == BackendAuthState.failed) {
      _attemptId = null;
    }
  }

  Future<void> _loadSessionCatalog() async {
    final generation = ++_sessionLoadGeneration;
    _replace(
      _state.copyWith(
        catalogMode: CatalogMode.loading,
        clearCatalogError: true,
      ),
    );
    try {
      final sessions = await _gateway.listSessions();
      if (generation != _sessionLoadGeneration) {
        return;
      }
      final storedSessionId = await _sessionStore.readSelectedSessionId();
      if (generation != _sessionLoadGeneration) {
        return;
      }
      final selectedSession = _getSelectedSession(sessions, storedSessionId);
      _replace(
        _state.copyWith(
          catalogMode: CatalogMode.ready,
          sessions: sessions,
          selectedSession: selectedSession,
          clearSelectedSession: selectedSession == null,
          clearCatalogError: true,
        ),
      );
      _beginAuthenticationIfReady();
    } on Object catch (error) {
      if (generation != _sessionLoadGeneration) {
        return;
      }
      _replace(
        _state.copyWith(
          catalogMode: CatalogMode.failed,
          catalogError: _getGreeterError(
            error,
            fallbackKind: GreeterErrorKind.session,
            recovery: GreeterRecovery.retrySessionCatalog,
          ),
        ),
      );
    }
  }

  SessionSummary? _getSelectedSession(
    List<SessionSummary> sessions,
    String? storedSessionId,
  ) {
    final current = _state.selectedSession;
    if (current != null &&
        sessions.any((candidate) => candidate.id == current.id)) {
      return current;
    }
    if (storedSessionId != null) {
      for (final session in sessions) {
        if (session.id == storedSessionId) {
          return session;
        }
      }
    }
    for (final preferred in _preferredSessionNames) {
      for (final session in sessions) {
        if (session.id.toLowerCase().contains(preferred) ||
            session.name.toLowerCase().contains(preferred)) {
          return session;
        }
      }
    }
    return sessions.isEmpty ? null : sessions.first;
  }

  void _resetToUserSelection({bool clearSelectedUser = false}) {
    _replace(
      _state.copyWith(
        authMode: AuthMode.userSelection,
        clearSelectedUser: clearSelectedUser,
        clearPrompt: true,
        clearAuthError: true,
        clearPromptError: true,
        clearCatalogError: _state.sessions.isNotEmpty,
        catalogMode: _state.sessions.isNotEmpty
            ? CatalogMode.ready
            : _state.catalogMode,
        backendAuthState: BackendAuthState.idle,
      ),
    );
  }

  void _showAuthError(GreeterError error) {
    _replace(
      _state.copyWith(
        authMode: AuthMode.error,
        authError: error,
        clearPromptError: true,
      ),
    );
  }

  void _showSessionError(GreeterError error) {
    _replace(
      _state.copyWith(
        authMode: AuthMode.sessionSelection,
        catalogMode: CatalogMode.ready,
        clearCatalogError: true,
      ),
    );
    _effects.add(ShowNoticeEffect(error.message, isError: true));
  }

  void _replace(GreeterState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    final nextSlots = GreeterSceneSlots.fromState(next);
    if (_serviceSlots.value != nextSlots.service) {
      _serviceSlots.value = nextSlots.service;
    }
    if (_authPromptSlots.value != nextSlots.authPrompt) {
      _authPromptSlots.value = nextSlots.authPrompt;
    }
    if (_accountPickerSlots.value != nextSlots.accountPicker) {
      _accountPickerSlots.value = nextSlots.accountPicker;
    }
    if (_sessionPickerSlots.value != nextSlots.sessionPicker) {
      _sessionPickerSlots.value = nextSlots.sessionPicker;
    }
    if (_powerSlots.value != nextSlots.power) {
      _powerSlots.value = nextSlots.power;
    }
    if (_dormantSlots.value != next.dormant) {
      _dormantSlots.value = next.dormant;
    }
  }

  GreeterError _getGreeterError(
    Object error, {
    required GreeterErrorKind fallbackKind,
    required GreeterRecovery recovery,
  }) {
    if (error is GreeterGatewayException) {
      return (kind: error.kind, message: error.message, recovery: recovery);
    }
    return (
      kind: fallbackKind,
      message: 'The greeter service is unavailable.',
      recovery: recovery,
    );
  }

  void dispose() {
    _disposed = true;
    unawaited(_eventSubscription?.cancel());
    unawaited(_gateway.close());
    unawaited(_effects.close());
    _serviceSlots.dispose();
    _authPromptSlots.dispose();
    _accountPickerSlots.dispose();
    _sessionPickerSlots.dispose();
    _powerSlots.dispose();
    _dormantSlots.dispose();
  }
}
