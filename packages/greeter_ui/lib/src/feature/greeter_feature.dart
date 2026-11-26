import 'dart:async';

import 'package:flutter/foundation.dart';

import 'greeter_commands.dart';
import 'greeter_effect.dart';
import 'greeter_slot_store.dart';
import 'greeter_slots.dart';
import 'greeter_state.dart';
import 'greeter_transitions.dart';
import 'ports/greeter_gateway.dart';
import 'ports/session_store.dart';

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
  final GreeterSlotStore _slots = GreeterSlotStore();
  StreamSubscription<GreeterEvent>? _eventSubscription;
  final List<GreeterEvent> _eventsDuringBegin = <GreeterEvent>[];
  GreeterState _state = GreeterState.initial();
  String? _attemptId;
  bool _initialized = false;
  bool _beginInFlight = false;
  bool _sessionStartInFlight = false;
  bool _disposed = false;
  int _serviceGeneration = 0;
  int _authGeneration = 0;
  int _sessionLoadGeneration = 0;

  GreeterState get state => _state;

  /// Composite notification triggered once per atomic feature update after all
  /// display slots have settled.
  Listenable get slotChanges => _slots.slotChanges;

  ValueListenable<ServiceSlots> get serviceSlots => _slots.serviceSlots;

  ValueListenable<AuthPromptSlots> get authPromptSlots =>
      _slots.authPromptSlots;

  ValueListenable<AccountPickerSlots> get accountPickerSlots =>
      _slots.accountPickerSlots;

  ValueListenable<SessionPickerSlots> get sessionPickerSlots =>
      _slots.sessionPickerSlots;

  ValueListenable<PowerSlots> get powerSlots => _slots.powerSlots;

  ValueListenable<bool> get dormantSlots => _slots.dormantSlots;

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
        await _retryAuthentication();
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
    final generation = _serviceGeneration;
    if (_state.serviceMode != ServiceMode.starting) {
      _updateState(_state.copyWith(serviceMode: ServiceMode.starting));
    }
    try {
      final snapshot = await gateway.getState();
      if (generation != _serviceGeneration) {
        return;
      }
      final users = await gateway.getUsers();
      if (generation != _serviceGeneration) {
        return;
      }
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
      if (generation != _serviceGeneration) {
        return;
      }
      _updateState(
        _state.copyWith(
          serviceMode: ServiceMode.unavailable,
          authMode: AuthMode.error,
          dormant: false,
          serviceError: createGreeterError(
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
    _invalidateServiceRequests();
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
        powerMode: PowerMode.idle,
        powerError: null,
        backendAuthState: BackendAuthState.idle,
      ),
    );
    await _loadService();
  }

  void _invalidateServiceRequests() {
    // Method replies may outlive a disconnect or reconnect. Invalidate their
    // continuations as well as signals so they cannot revive the old service.
    _serviceGeneration++;
    _authGeneration++;
    _sessionLoadGeneration++;
    _attemptId = null;
    _beginInFlight = false;
    _sessionStartInFlight = false;
    _eventsDuringBegin.clear();
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

  bool get _canSelectUser => canSelectGreeterUser(
    _state,
    beginInFlight: _beginInFlight,
    sessionStartInFlight: _sessionStartInFlight,
  );

  Future<void> _selectUser(UserSummary user) async {
    if (!_canSelectUser ||
        !_state.users.any((candidate) => candidate.id == user.id) ||
        (_attemptId != null && _state.selectedUser?.id == user.id)) {
      return;
    }
    if (_attemptId != null) {
      final generation = _serviceGeneration;
      await _cancelAuthentication();
      if (generation != _serviceGeneration ||
          _state.serviceMode != ServiceMode.ready) {
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
    final generation = _serviceGeneration;
    final authGeneration = ++_authGeneration;
    try {
      // Signals can precede the reply that supplies the attempt ID. Replay
      // them only after binding that ID, preserving order and stale filtering.
      final attemptId = await gateway.beginAuthentication(user.id);
      if (generation != _serviceGeneration) {
        return;
      }
      if (authGeneration != _authGeneration) {
        _eventsDuringBegin.clear();
        _beginInFlight = false;
        unawaited(_cancelOrphanedAttempt(attemptId));
        return;
      }
      _attemptId = attemptId;
      final pendingEvents = List<GreeterEvent>.from(_eventsDuringBegin);
      _eventsDuringBegin.clear();
      _beginInFlight = false;
      for (final event in pendingEvents) {
        _handleEvent(event);
      }
    } on Object catch (error) {
      if (generation != _serviceGeneration ||
          authGeneration != _authGeneration) {
        return;
      }
      _eventsDuringBegin.clear();
      _beginInFlight = false;
      _setAuthError(
        createGreeterError(
          error,
          fallbackKind: GreeterErrorKind.authentication,
          recovery: GreeterRecovery.retryAuthentication,
        ),
      );
    }
  }

  Future<void> _cancelOrphanedAttempt(String attemptId) async {
    try {
      await gateway.cancel(attemptId);
    } on Object {
      // Best-effort cleanup when a pending start was cancelled before reply.
    }
  }

  Future<void> _respondToPrompt(String response) async {
    final attemptId = _attemptId;
    if (attemptId == null || _state.authMode != AuthMode.prompting) {
      return;
    }
    final isEmptyResponse = _state.prompt?.kind == PromptKind.secret
        ? response.isEmpty
        : response.trim().isEmpty;
    if (isEmptyResponse) {
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
          createGreeterError(
            error,
            fallbackKind: GreeterErrorKind.authentication,
            recovery: GreeterRecovery.retryAuthentication,
          ),
        );
      }
    }
  }

  Future<void> _cancelAuthentication() async {
    _authGeneration++;
    final attemptId = _attemptId;
    if (attemptId == null) {
      _beginInFlight = false;
      _eventsDuringBegin.clear();
      _resetToUserSelection(clearSelectedUser: true);
      return;
    }

    // Invalidate locally before awaiting cancellation; late prompts from the
    // abandoned conversation must no longer be able to restore the input UI.
    _attemptId = null;
    final generation = _serviceGeneration;
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
      if (generation != _serviceGeneration) {
        return;
      }
      // If the attempt already ended on the backend (stale/unknown attempt id),
      // treat the non-transport error as cancelled instead of breaking service.
      if (error is GreeterGatewayException &&
          error.kind != GreeterErrorKind.transport) {
        _resetToUserSelection(clearSelectedUser: true);
        return;
      }
      _updateState(
        _state.copyWith(
          serviceMode: ServiceMode.unavailable,
          authMode: AuthMode.error,
          dormant: false,
          serviceError: createGreeterError(
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
    if (generation != _serviceGeneration) {
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
    final generation = _serviceGeneration;
    _updateState(
      _state.copyWith(authMode: AuthMode.submitting, catalogError: null),
    );
    try {
      await gateway.startSession(attemptId, session.id);
      if (generation != _serviceGeneration || attemptId != _attemptId) {
        return;
      }
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
      if (generation != _serviceGeneration || attemptId != _attemptId) {
        return;
      }
      _updateState(
        _state.copyWith(
          authMode: AuthMode.sessionSelection,
          catalogMode: CatalogMode.ready,
          catalogError: null,
        ),
      );
      _effects.add(ShowErrorNoticeEffect(getGreeterErrorMessage(error)));
    } finally {
      if (generation == _serviceGeneration) {
        _sessionStartInFlight = false;
      }
    }
  }

  Future<void> _requestPowerAction(PowerAction action) async {
    if (_state.powerMode == PowerMode.executing) {
      return;
    }
    final generation = _serviceGeneration;
    _updateState(
      _state.copyWith(powerMode: PowerMode.executing, powerError: null),
    );
    try {
      await gateway.requestPowerAction(action);
      if (generation != _serviceGeneration) {
        return;
      }
      _updateState(_state.copyWith(powerMode: PowerMode.succeeded));
    } on Object catch (error) {
      if (generation != _serviceGeneration) {
        return;
      }
      final powerError = createGreeterError(
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

  Future<void> _retryAuthentication() async {
    if (_state.serviceMode != ServiceMode.ready) {
      return;
    }
    _authGeneration++;
    final orphanedAttempt = _attemptId;
    _attemptId = null;
    _resetToUserSelection(serviceMode: ServiceMode.ready);
    if (orphanedAttempt != null) {
      final generation = _serviceGeneration;
      await _cancelOrphanedAttempt(orphanedAttempt);
      if (generation != _serviceGeneration ||
          _state.serviceMode != ServiceMode.ready) {
        return;
      }
    }
    unawaited(_beginAuthentication());
  }

  void _retryPrompt() {
    if (_attemptId == null || _state.prompt == null) {
      unawaited(_retryAuthentication());
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
        _invalidateServiceRequests();
        _updateState(
          _state.copyWith(
            serviceMode: ServiceMode.unavailable,
            authMode: AuthMode.error,
            dormant: false,
            powerMode: PowerMode.idle,
            powerError: null,
            serviceError: const (
              kind: GreeterErrorKind.transport,
              message: serviceUnavailableMessage,
              recovery: GreeterRecovery.reconnectService,
            ),
          ),
        );
        _effects.add(const ClearCredentialEffect());
      case BackendStateChanged(:final state, :final detail):
        final outcome = applyBackendAuthStateTransition(_state, state, detail);
        if (outcome.clearAttempt) {
          _attemptId = null;
        }
        if (outcome.effect case final effect?) {
          _effects.add(effect);
        }
        _updateState(outcome.state);
        if (outcome.shouldStartSession) {
          unawaited(_startSelectedSession());
        }
      case BackendPromptReceived(:final kind, :final text):
        final outcome = applyPromptTransition(_state, kind, text);
        _updateState(outcome.state);
        if (outcome.effect case final effect?) {
          _effects.add(effect);
        }
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
      final selectedSession = findPreferredSession(
        sessions,
        current: _state.selectedSession,
        storedSessionId: storedSessionId,
      );
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
          catalogError: createGreeterError(
            error,
            fallbackKind: GreeterErrorKind.session,
            recovery: GreeterRecovery.retrySessionCatalog,
          ),
        ),
      );
    }
  }

  void _resetToUserSelection({
    bool clearSelectedUser = false,
    ServiceMode? serviceMode,
  }) {
    _updateState(
      resetGreeterStateToUserSelection(
        _state,
        clearSelectedUser: clearSelectedUser,
        serviceMode: serviceMode,
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
    _slots.sync(next, canSelectUser: _canSelectUser);
  }

  void dispose() {
    _disposed = true;
    _invalidateServiceRequests();
    unawaited(_eventSubscription?.cancel());
    unawaited(gateway.close());
    unawaited(_effects.close());
    _slots.dispose();
  }
}
