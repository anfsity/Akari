import 'dart:async';

import 'package:flutter/foundation.dart';

import 'greeter_commands.dart';
import 'greeter_effect.dart';
import 'greeter_slots.dart';
import 'greeter_state.dart';
import 'ports/greeter_gateway.dart';

/// Application-facing state owner for the greeter flow.
///
/// This is deliberately independent from Scene widgets. D-Bus is represented
/// by [GreeterGateway] and never accessed directly from this class.
class GreeterFeature {
  // The public parameter name cannot use the library-private field name.
  // ignore: prefer_initializing_formals
  GreeterFeature({required GreeterGateway gateway}) : _gateway = gateway;

  final GreeterGateway _gateway;
  final StreamController<FeatureEffect> _effects =
      StreamController<FeatureEffect>.broadcast();
  StreamSubscription<GreeterEvent>? _eventSubscription;
  final List<GreeterEvent> _eventsDuringBegin = <GreeterEvent>[];
  final ValueNotifier<ServiceSlots> _serviceSlots = ValueNotifier(
    const ServiceSlots(mode: ServiceMode.starting, error: null),
  );
  final ValueNotifier<AuthPromptSlots> _authPromptSlots = ValueNotifier(
    AuthPromptSlots(
      mode: AuthMode.userSelection,
      selectedUser: null,
      prompt: null,
      error: null,
    ),
  );
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
  final ValueNotifier<ContinueSlots> _continueSlots = ValueNotifier(
    const ContinueSlots(enabled: false),
  );
  final ValueNotifier<PowerSlots> _powerSlots = ValueNotifier(
    const PowerSlots(mode: PowerMode.idle, error: null),
  );
  final ValueNotifier<BackgroundSlots> _backgroundSlots = ValueNotifier(
    BackgroundSlots.fromAuthMode(AuthMode.userSelection),
  );
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

  ValueListenable<ContinueSlots> get continueSlots => _continueSlots;

  ValueListenable<PowerSlots> get powerSlots => _powerSlots;

  ValueListenable<BackgroundSlots> get backgroundSlots => _backgroundSlots;

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
            authError: GreeterError(
              kind: GreeterErrorKind.authentication,
              message: snapshot.detail.isEmpty
                  ? 'The greeter service has an active authentication transaction.'
                  : snapshot.detail,
              recovery: GreeterRecovery.reconnectService,
            ),
            clearServiceError: true,
          ),
        );
        return;
      }
      _replace(
        _state.copyWith(
          serviceMode: ServiceMode.ready,
          users: users,
          authMode: AuthMode.userSelection,
          backendAuthState: snapshot.state,
          catalogMode: CatalogMode.loading,
          sessions: const [],
          clearSelectedSession: true,
          clearServiceError: true,
          clearAuthError: true,
        ),
      );
      unawaited(_loadSessionCatalog());
    } on Object catch (error) {
      _replace(
        _state.copyWith(
          serviceMode: ServiceMode.unavailable,
          authMode: AuthMode.error,
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
        backendAuthState: BackendAuthState.idle,
      ),
    );
    await _loadService();
  }

  void _selectUser(UserSummary user) {
    if (_state.serviceMode != ServiceMode.ready ||
        !_state.users.any((candidate) => candidate.id == user.id)) {
      return;
    }
    _replace(_state.copyWith(selectedUser: user, clearAuthError: true));
  }

  Future<void> _beginAuthentication() async {
    final user = _state.selectedUser;
    if (user == null ||
        _state.selectedSession == null ||
        _state.authMode == AuthMode.submitting) {
      return;
    }

    _replace(
      _state.copyWith(authMode: AuthMode.submitting, clearAuthError: true),
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
      _showAuthError(
        const GreeterError(
          kind: GreeterErrorKind.input,
          message: 'A response is required.',
          recovery: GreeterRecovery.retryPrompt,
        ),
      );
      return;
    }

    _replace(
      _state.copyWith(authMode: AuthMode.submitting, clearAuthError: true),
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
          serviceError: _getGreeterError(
            error,
            fallbackKind: GreeterErrorKind.transport,
            recovery: GreeterRecovery.reconnectService,
          ),
          clearAuthError: true,
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
      ),
    );
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
        clearCatalogError: _state.sessions.isNotEmpty,
        catalogMode: _state.sessions.isNotEmpty
            ? CatalogMode.ready
            : _state.catalogMode,
        backendAuthState: BackendAuthState.idle,
      ),
    );
  }

  void _retryPrompt() {
    if (_attemptId == null || _state.prompt == null) {
      _retryAuthentication();
      return;
    }
    _replace(
      _state.copyWith(authMode: AuthMode.prompting, clearAuthError: true),
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
            serviceError: const GreeterError(
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
              prompt: PromptState(kind: kind, text: text),
              backendAuthState: BackendAuthState.waitingForInput,
              clearAuthError: true,
            ),
          );
          _effects.add(const RequestFocusEffect('credential'));
        } else {
          _effects.add(
            ShowNoticeEffect(text, isError: kind == PromptKind.error),
          );
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
            ? GreeterError(
                kind: GreeterErrorKind.authentication,
                message: detail,
                recovery: GreeterRecovery.retryAuthentication,
              )
            : null,
        clearAuthError: state != BackendAuthState.failed,
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
      final selectedSession = _state.selectedSession;
      final selectedStillAvailable =
          selectedSession != null &&
          sessions.any((candidate) => candidate.id == selectedSession.id);
      _replace(
        _state.copyWith(
          catalogMode: CatalogMode.ready,
          sessions: sessions,
          clearSelectedSession:
              selectedSession != null && !selectedStillAvailable,
          clearCatalogError: true,
        ),
      );
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

  void _resetToUserSelection({bool clearSelectedUser = false}) {
    _replace(
      _state.copyWith(
        authMode: AuthMode.userSelection,
        clearSelectedUser: clearSelectedUser,
        clearPrompt: true,
        clearAuthError: true,
        clearCatalogError: _state.sessions.isNotEmpty,
        catalogMode: _state.sessions.isNotEmpty
            ? CatalogMode.ready
            : _state.catalogMode,
        backendAuthState: BackendAuthState.idle,
      ),
    );
  }

  void _showAuthError(GreeterError error) {
    _replace(_state.copyWith(authMode: AuthMode.error, authError: error));
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
    if (_continueSlots.value != nextSlots.continueAction) {
      _continueSlots.value = nextSlots.continueAction;
    }
    if (_powerSlots.value != nextSlots.power) {
      _powerSlots.value = nextSlots.power;
    }
    if (_backgroundSlots.value != nextSlots.background) {
      _backgroundSlots.value = nextSlots.background;
    }
  }

  GreeterError _getGreeterError(
    Object error, {
    required GreeterErrorKind fallbackKind,
    required GreeterRecovery recovery,
  }) {
    if (error is GreeterGatewayException) {
      return GreeterError(
        kind: error.kind,
        message: error.message,
        recovery: recovery,
      );
    }
    return GreeterError(
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
    _continueSlots.dispose();
    _powerSlots.dispose();
    _backgroundSlots.dispose();
  }
}
