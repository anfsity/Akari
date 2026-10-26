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

class _SlotChangeNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Application-facing state owner for the greeter flow.
///
/// This is deliberately independent from Scene widgets. D-Bus is represented
/// by [GreeterGateway] and never accessed directly from this class.
/// Attempt IDs isolate authentication events; catalog generations isolate
/// asynchronous reloads. Neither visual state nor slots retain credential
/// responses. Durable state is projected into region listenables, while focus,
/// notices, and process exit travel through the one-shot [effects] stream.
class GreeterFeature {
  GreeterFeature({
    required this.gateway,
    this.sessionStore = const NoopSessionStore(),
  });

  final GreeterGateway gateway;
  final SessionStore sessionStore;
  final StreamController<FeatureEffect> _effects =
      StreamController<FeatureEffect>.broadcast();
  final _SlotChangeNotifier _slotChanges = _SlotChangeNotifier();
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
    AccountPickerSlots(users: const [], selected: null, canSelect: false),
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

  /// Composite notification triggered once per atomic feature update after all
  /// display slots have settled.
  Listenable get slotChanges => _slotChanges;

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
        await _selectUser(user);
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
    // Subscribe before querying: backend signals may arrive while a method
    // reply is pending and must not be lost during initial service loading.
    _eventSubscription = gateway.events.listen(_handleEvent);
    await _loadService();
  }

  Future<void> _loadService() async {
    if (_state.serviceMode != ServiceMode.starting) {
      _updateState(_state.copyWith(serviceMode: ServiceMode.starting));
    }
    try {
      final snapshot = await gateway.getState();
      final users = await gateway.getUsers();
      // GetState has no attempt token. An existing conversation cannot be
      // adopted by this client, so expose recovery instead of inventing one.
      if (snapshot.state != BackendAuthState.idle) {
        _updateState(
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
            promptError: null,
            dormant: false,
            serviceError: null,
          ),
        );
        return;
      }
      _updateState(
        _state.copyWith(
          serviceMode: ServiceMode.ready,
          users: users,
          selectedUser: users.length == 1 ? users.first : null,
          authMode: AuthMode.userSelection,
          backendAuthState: snapshot.state,
          catalogMode: CatalogMode.loading,
          sessions: const [],
          selectedSession: null,
          serviceError: null,
          authError: null,
          promptError: null,
        ),
      );
      unawaited(_loadSessionCatalog());
    } on Object catch (error) {
      _updateState(
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
    _updateState(
      _state.copyWith(
        serviceMode: ServiceMode.starting,
        authMode: AuthMode.userSelection,
        serviceError: null,
        authError: null,
        catalogError: null,
        catalogMode: CatalogMode.empty,
        sessions: const [],
        selectedUser: null,
        selectedSession: null,
        prompt: null,
        promptError: null,
        backendAuthState: BackendAuthState.idle,
      ),
    );
    await _loadService();
  }

  void _wakeGreeter() {
    if (!_state.dormant || _state.serviceMode != ServiceMode.ready) {
      return;
    }
    _updateState(_state.copyWith(dormant: false));
    unawaited(_beginAuthentication());
  }

  void _sleepGreeter() {
    if (_state.dormant ||
        _state.serviceMode != ServiceMode.ready ||
        _state.authMode == AuthMode.handingOff) {
      return;
    }
    // Hiding the form does not abandon its PAM conversation. Cancelling an
    // unanswered password prompt can count as a failure on the host, so wake
    // resumes the same attempt instead of creating another login attempt.
    _updateState(_state.copyWith(dormant: true));
  }

  bool get _canSelectUser {
    if (_state.serviceMode != ServiceMode.ready ||
        _state.dormant ||
        _beginInFlight ||
        _sessionStartInFlight) {
      return false;
    }
    if (_state.authMode == AuthMode.userSelection ||
        _state.authMode == AuthMode.prompting ||
        (_state.authMode == AuthMode.submitting &&
            _state.prompt?.kind == PromptKind.info)) {
      return true;
    }
    return _state.authMode == AuthMode.error &&
        (_state.authError?.recovery == GreeterRecovery.retryAuthentication ||
            _state.authError?.recovery == GreeterRecovery.retryPrompt);
  }

  Future<void> _selectUser(UserSummary user) async {
    if (!_canSelectUser ||
        !_state.users.any((candidate) => candidate.id == user.id) ||
        (_attemptId != null && _state.selectedUser?.id == user.id)) {
      return;
    }
    if (_attemptId != null) {
      await _cancelAuthentication();
      if (_state.serviceMode != ServiceMode.ready) {
        return;
      }
    }
    _updateState(
      _state.copyWith(
        authMode: AuthMode.userSelection,
        selectedUser: user,
        prompt: null,
        authError: null,
        promptError: null,
        backendAuthState: BackendAuthState.idle,
      ),
    );
    unawaited(_beginAuthentication());
  }

  Future<void> _beginAuthentication() async {
    if (_state.dormant) {
      return;
    }
    final user = _state.selectedUser;
    if (user == null ||
        _state.selectedSession == null ||
        _state.authMode != AuthMode.userSelection) {
      return;
    }

    _updateState(
      _state.copyWith(
        authMode: AuthMode.submitting,
        authError: null,
        promptError: null,
      ),
    );

    _beginInFlight = true;
    _eventsDuringBegin.clear();
    try {
      // Signals can precede the reply that supplies the attempt ID. Replay
      // them only after binding that ID, preserving order and stale filtering.
      final attemptId = await gateway.beginAuthentication(user.id);
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
      _setAuthError(
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
      _setAuthError(const (
        kind: GreeterErrorKind.input,
        message: 'A response is required.',
        recovery: GreeterRecovery.retryPrompt,
      ));
      return;
    }

    _updateState(
      _state.copyWith(
        authMode: AuthMode.submitting,
        authError: null,
        promptError: null,
      ),
    );
    try {
      await gateway.respond(attemptId, response);
    } on Object catch (error) {
      if (attemptId == _attemptId) {
        _setAuthError(
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

    // Invalidate locally before awaiting cancellation; late prompts from the
    // abandoned conversation must no longer be able to restore the input UI.
    _attemptId = null;
    _updateState(
      _state.copyWith(
        authMode: AuthMode.submitting,
        backendAuthState: BackendAuthState.cancelling,
        prompt: null,
        authError: null,
        promptError: null,
      ),
    );
    try {
      await gateway.cancel(attemptId);
    } on Object catch (error) {
      _updateState(
        _state.copyWith(
          serviceMode: ServiceMode.unavailable,
          authMode: AuthMode.error,
          dormant: false,
          serviceError: _getGreeterError(
            error,
            fallbackKind: GreeterErrorKind.transport,
            recovery: GreeterRecovery.reconnectService,
          ),
          authError: null,
          promptError: null,
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
    _updateState(_state.copyWith(selectedSession: session, catalogError: null));
    unawaited(sessionStore.saveSelectedSessionId(session.id));
    unawaited(_beginAuthentication());
  }

  Future<void> _startSelectedSession() async {
    final attemptId = _attemptId;
    final session = _state.selectedSession;
    if (attemptId == null || session == null || _sessionStartInFlight) {
      return;
    }

    _sessionStartInFlight = true;
    _updateState(
      _state.copyWith(authMode: AuthMode.submitting, catalogError: null),
    );
    try {
      await gateway.startSession(attemptId, session.id);
      _updateState(
        _state.copyWith(
          authMode: AuthMode.handingOff,
          authError: null,
          catalogError: null,
        ),
      );
      _effects.add(const ExitAfterHandoffEffect());
    } on Object catch (error) {
      // A Failed signal can invalidate this attempt before the method reply.
      // Preserve its authentication recovery instead of offering a session retry.
      if (attemptId != _attemptId) {
        return;
      }
      _updateState(
        _state.copyWith(
          authMode: AuthMode.sessionSelection,
          catalogMode: CatalogMode.ready,
          catalogError: null,
        ),
      );
      _effects.add(ShowErrorNoticeEffect(_getErrorMessage(error)));
    } finally {
      _sessionStartInFlight = false;
    }
  }

  Future<void> _requestPowerAction(PowerAction action) async {
    if (_state.powerMode == PowerMode.executing) {
      return;
    }
    _updateState(
      _state.copyWith(powerMode: PowerMode.executing, powerError: null),
    );
    try {
      await gateway.requestPowerAction(action);
      _updateState(_state.copyWith(powerMode: PowerMode.succeeded));
    } on Object catch (error) {
      final powerError = _getGreeterError(
        error,
        fallbackKind: GreeterErrorKind.power,
        recovery: GreeterRecovery.selectUser,
      );
      _updateState(
        _state.copyWith(powerMode: PowerMode.failed, powerError: powerError),
      );
      _effects.add(ShowErrorNoticeEffect(powerError.message));
    }
  }

  void _retryAuthentication() {
    _attemptId = null;
    _resetToUserSelection(serviceMode: ServiceMode.ready);
    unawaited(_beginAuthentication());
  }

  void _retryPrompt() {
    if (_attemptId == null || _state.prompt == null) {
      _retryAuthentication();
      return;
    }
    _updateState(
      _state.copyWith(
        authMode: AuthMode.prompting,
        authError: null,
        promptError: null,
      ),
    );
    _effects.add(const FocusCredentialEffect());
  }

  Future<void> _retrySessionCatalog() async {
    if (_state.serviceMode != ServiceMode.ready) {
      return;
    }
    await _loadSessionCatalog();
  }

  void _handleEvent(GreeterEvent event) {
    if (event case AuthenticationEvent(:final attemptId)) {
      if (_attemptId == null && _beginInFlight) {
        _eventsDuringBegin.add(event);
        return;
      }
      if (attemptId != _attemptId) {
        return;
      }
    }
    switch (event) {
      case BackendDisconnected():
        _attemptId = null;
        _updateState(
          _state.copyWith(
            serviceMode: ServiceMode.unavailable,
            authMode: AuthMode.error,
            dormant: false,
            serviceError: const (
              kind: GreeterErrorKind.transport,
              message: serviceUnavailableMessage,
              recovery: GreeterRecovery.reconnectService,
            ),
          ),
        );
      case BackendStateChanged(:final state, :final detail):
        _applyBackendState(state, detail);
      case BackendPromptReceived(:final kind, :final text):
        _applyPrompt(kind, text);
    }
  }

  void _applyPrompt(PromptKind kind, String text) {
    switch (kind) {
      case PromptKind.visible:
      case PromptKind.secret:
        _updateState(
          _state.copyWith(
            authMode: AuthMode.prompting,
            prompt: (kind: kind, text: text),
            backendAuthState: BackendAuthState.waitingForInput,
            authError: null,
          ),
        );
        _effects.add(const FocusCredentialEffect());
      case PromptKind.error:
        _updateState(_state.copyWith(promptError: text));
      case PromptKind.info:
        // PAM acknowledges passive authentication in the backend. Keep its
        // instructions visible for the scan without requesting credentials.
        _updateState(
          _state.copyWith(
            authMode: AuthMode.submitting,
            prompt: (kind: kind, text: text),
            authError: null,
            promptError: null,
          ),
        );
        _effects.add(const ClearCredentialEffect());
    }
  }

  void _applyBackendState(BackendAuthState state, String detail) {
    final failed = state == BackendAuthState.failed;
    final clearPrompt = failed || state == BackendAuthState.authenticated;
    final preserveAuthMode =
        state == BackendAuthState.waitingForInput ||
        state == BackendAuthState.unknown;
    if (failed) {
      _attemptId = null;
    }
    // Prompt carries the input kind and text; WaitingForInput only confirms
    // protocol progress. Keeping the current mode avoids undoing that prompt
    // or a local input error when the following state signal arrives.
    final nextMode = switch (state) {
      BackendAuthState.creatingSession ||
      BackendAuthState.promptPending ||
      BackendAuthState.submittingResponse ||
      BackendAuthState.resolvingSession ||
      BackendAuthState.startingSession ||
      BackendAuthState.cancelling => AuthMode.submitting,
      BackendAuthState.authenticated =>
        _state.selectedSession == null
            ? AuthMode.sessionSelection
            : AuthMode.submitting,
      BackendAuthState.handingOff => AuthMode.handingOff,
      BackendAuthState.failed => AuthMode.error,
      BackendAuthState.idle => AuthMode.userSelection,
      BackendAuthState.waitingForInput ||
      BackendAuthState.unknown => _state.authMode,
    };

    final authError = failed
        ? (
            kind: GreeterErrorKind.authentication,
            message: detail,
            recovery: GreeterRecovery.retryAuthentication,
          )
        : preserveAuthMode
        ? _state.authError
        : null;

    _updateState(
      _state.copyWith(
        authMode: nextMode,
        backendAuthState: state,
        authError: authError,
        promptError: clearPrompt ? null : _state.promptError,
        prompt: clearPrompt ? null : _state.prompt,
      ),
    );
    if (state == BackendAuthState.authenticated &&
        _state.selectedSession != null) {
      unawaited(_startSelectedSession());
    }
  }

  Future<void> _loadSessionCatalog() async {
    // Both the backend scan and preference read yield. A retry or reconnect
    // invalidates earlier loads at each await boundary, including their errors.
    final generation = ++_sessionLoadGeneration;
    _updateState(
      _state.copyWith(catalogMode: CatalogMode.loading, catalogError: null),
    );
    try {
      final sessions = await gateway.getSessions();
      if (generation != _sessionLoadGeneration) {
        return;
      }
      final storedSessionId = await sessionStore.findSelectedSessionId();
      if (generation != _sessionLoadGeneration) {
        return;
      }
      final selectedSession = _getSelectedSession(sessions, storedSessionId);
      _updateState(
        _state.copyWith(
          catalogMode: sessions.isEmpty ? CatalogMode.empty : CatalogMode.ready,
          sessions: sessions,
          selectedSession: selectedSession,
          catalogError: null,
        ),
      );
      unawaited(_beginAuthentication());
    } on Object catch (error) {
      if (generation != _sessionLoadGeneration) {
        return;
      }
      _updateState(
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
    // A refresh preserves the current choice before consulting persistence.
    // Only IDs present in this catalog may be restored; preferences are hints,
    // not authority to launch a session that the backend no longer exposes.
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

  void _resetToUserSelection({
    bool clearSelectedUser = false,
    ServiceMode? serviceMode,
  }) {
    _updateState(
      _state.copyWith(
        serviceMode: serviceMode,
        authMode: AuthMode.userSelection,
        selectedUser: clearSelectedUser ? null : _state.selectedUser,
        prompt: null,
        authError: null,
        promptError: null,
        catalogError: _state.sessions.isNotEmpty ? null : _state.catalogError,
        catalogMode: _state.sessions.isNotEmpty
            ? CatalogMode.ready
            : _state.catalogMode,
        backendAuthState: BackendAuthState.idle,
      ),
    );
  }

  void _setAuthError(GreeterError error) {
    _updateState(
      _state.copyWith(
        authMode: AuthMode.error,
        authError: error,
        promptError: null,
      ),
    );
  }

  void _updateState(GreeterState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    // ValueNotifier compares semantic slot equality before notifying, so
    // unrelated transitions do not rebuild every region of the scene.
    var slotsChanged = false;
    slotsChanged |= _setSlot(_serviceSlots, (
      mode: next.serviceMode,
      error: next.serviceError,
    ));
    slotsChanged |= _setSlot(_authPromptSlots, (
      mode: next.authMode,
      // Account selection belongs to its picker until authentication starts;
      // hiding it here keeps the prompt region from presenting a partial flow.
      selectedUser: next.authMode == AuthMode.userSelection
          ? null
          : next.selectedUser,
      prompt: next.prompt,
      error: next.authError,
      promptError: next.promptError,
    ));
    slotsChanged |= _setSlot(
      _accountPickerSlots,
      AccountPickerSlots(
        users: next.users,
        selected: next.selectedUser,
        canSelect: _canSelectUser,
      ),
    );
    slotsChanged |= _setSlot(
      _sessionPickerSlots,
      SessionPickerSlots(
        mode: next.catalogMode,
        sessions: next.sessions,
        selected: next.selectedSession,
        error: next.catalogError,
      ),
    );
    slotsChanged |= _setSlot(_powerSlots, (
      mode: next.powerMode,
      error: next.powerError,
    ));
    _dormantSlots.value = next.dormant;
    if (slotsChanged) {
      _slotChanges.notify();
    }
  }

  static bool _setSlot<T>(ValueNotifier<T> slot, T next) {
    if (slot.value == next) {
      return false;
    }
    slot.value = next;
    return true;
  }

  String _getErrorMessage(Object error) {
    return error is GreeterGatewayException
        ? error.message
        : serviceUnavailableMessage;
  }

  GreeterError _getGreeterError(
    Object error, {
    required GreeterErrorKind fallbackKind,
    required GreeterRecovery recovery,
  }) {
    return (
      kind: error is GreeterGatewayException ? error.kind : fallbackKind,
      message: _getErrorMessage(error),
      recovery: recovery,
    );
  }

  void dispose() {
    _disposed = true;
    unawaited(_eventSubscription?.cancel());
    unawaited(gateway.close());
    unawaited(_effects.close());
    _slotChanges.dispose();
    _serviceSlots.dispose();
    _authPromptSlots.dispose();
    _accountPickerSlots.dispose();
    _sessionPickerSlots.dispose();
    _powerSlots.dispose();
    _dormantSlots.dispose();
  }
}
