import 'dart:async';

import 'package:flutter/foundation.dart';

import 'greeter_effect.dart';
import 'greeter_slots.dart';
import 'greeter_state.dart';
import 'ports/greeter_gateway.dart';

/// Application-facing state owner for the greeter flow.
///
/// This is deliberately independent from Scene widgets. D-Bus is represented
/// by [GreeterGateway] and never accessed directly from this class.
class GreeterFeature extends ChangeNotifier {
  // The public parameter name cannot use the library-private field name.
  // ignore: prefer_initializing_formals
  GreeterFeature({required GreeterGateway gateway}) : _gateway = gateway;

  final GreeterGateway _gateway;
  final StreamController<FeatureEffect> _effects =
      StreamController<FeatureEffect>.broadcast();
  StreamSubscription<GreeterEvent>? _eventSubscription;
  final List<GreeterEvent> _eventsDuringBegin = <GreeterEvent>[];

  GreeterState _state = GreeterState.initial();
  String? _attemptId;
  bool _initialized = false;
  bool _beginInFlight = false;

  GreeterState get state => _state;

  GreeterSceneSlots get slots => GreeterSceneSlots.fromState(_state);

  Stream<FeatureEffect> get effects => _effects.stream;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _eventSubscription = _gateway.events.listen(_handleEvent);

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
            error: snapshot.detail.isEmpty
                ? 'The greeter service has an active authentication transaction.'
                : snapshot.detail,
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
          clearError: true,
        ),
      );
    } on Object catch (error) {
      _replace(
        _state.copyWith(
          serviceMode: ServiceMode.unavailable,
          authMode: AuthMode.error,
          error: _getDisplayError(error),
        ),
      );
    }
  }

  void selectUser(UserSummary user) {
    if (_state.serviceMode != ServiceMode.ready) {
      return;
    }
    _replace(
      _state.copyWith(
        selectedUser: user,
        authMode: AuthMode.editing,
        clearError: true,
      ),
    );
  }

  Future<void> beginAuthentication() async {
    final user = _state.selectedUser;
    if (user == null || _state.authMode == AuthMode.submitting) {
      return;
    }

    _replace(_state.copyWith(authMode: AuthMode.submitting, clearError: true));

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
      _showError(error);
    }
  }

  Future<void> respondToPrompt(String response) async {
    final attemptId = _attemptId;
    if (attemptId == null || _state.authMode != AuthMode.prompting) {
      return;
    }

    _replace(_state.copyWith(authMode: AuthMode.submitting));
    try {
      await _gateway.respond(attemptId, response);
      if (attemptId != _attemptId) {
        return;
      }
    } on Object catch (error) {
      if (attemptId == _attemptId) {
        _showError(error);
      }
    }
  }

  Future<void> cancelAuthentication() async {
    final attemptId = _attemptId;
    if (attemptId == null) {
      _resetToUserSelection(clearSelectedUser: true);
      return;
    }

    _attemptId = null;
    try {
      await _gateway.cancel(attemptId);
    } finally {
      _resetToUserSelection(clearSelectedUser: true);
    }
  }

  void selectSession(SessionSummary session) {
    if (_state.authMode != AuthMode.sessionSelection) {
      return;
    }
    _replace(_state.copyWith(selectedSession: session, clearError: true));
  }

  Future<void> startSelectedSession() async {
    final attemptId = _attemptId;
    final session = _state.selectedSession;
    if (attemptId == null || session == null) {
      return;
    }

    _replace(_state.copyWith(authMode: AuthMode.submitting));
    try {
      await _gateway.startSession(attemptId, session.id);
      _replace(_state.copyWith(authMode: AuthMode.handingOff));
      _effects.add(const ExitAfterHandoffEffect());
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> requestPowerAction(PowerAction action) async {
    if (_state.powerMode == PowerMode.executing) {
      return;
    }
    _replace(_state.copyWith(powerMode: PowerMode.executing));
    try {
      await _gateway.powerAction(action);
      _replace(_state.copyWith(powerMode: PowerMode.succeeded));
    } on Object catch (error) {
      _replace(
        _state.copyWith(
          powerMode: PowerMode.failed,
          error: _getDisplayError(error),
        ),
      );
    }
  }

  void retry() {
    _attemptId = null;
    _replace(
      _state.copyWith(
        serviceMode: ServiceMode.ready,
        authMode: _state.selectedUser == null
            ? AuthMode.userSelection
            : AuthMode.editing,
        clearPrompt: true,
        clearError: true,
        clearSelectedSession: true,
      ),
    );
  }

  void _handleEvent(GreeterEvent event) {
    switch (event) {
      case BackendDisconnected():
        _attemptId = null;
        _replace(
          _state.copyWith(
            serviceMode: ServiceMode.unavailable,
            authMode: AuthMode.error,
            error: 'The greeter service is unavailable.',
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
              clearError: true,
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
      BackendAuthState.authenticated => AuthMode.sessionSelection,
      BackendAuthState.handingOff => AuthMode.handingOff,
      BackendAuthState.failed => AuthMode.error,
      BackendAuthState.cancelling => AuthMode.submitting,
      BackendAuthState.idle => AuthMode.userSelection,
      BackendAuthState.waitingForInput => _state.authMode,
      BackendAuthState.unknown => _state.authMode,
    };

    if (state == BackendAuthState.authenticated && _state.sessions.isEmpty) {
      unawaited(_loadSessionsForCurrentAttempt());
    }

    _replace(
      _state.copyWith(
        authMode: nextMode,
        backendAuthState: state,
        error: state == BackendAuthState.failed ? detail : null,
        clearError: state != BackendAuthState.failed,
        clearPrompt:
            state == BackendAuthState.authenticated ||
            state == BackendAuthState.failed,
      ),
    );
    if (state == BackendAuthState.failed) {
      _attemptId = null;
    }
  }

  Future<void> _loadSessionsForCurrentAttempt() async {
    final attemptId = _attemptId;
    if (attemptId == null) {
      return;
    }
    try {
      final sessions = await _gateway.listSessions();
      if (attemptId == _attemptId) {
        _replace(_state.copyWith(sessions: sessions));
      }
    } on Object catch (error) {
      if (attemptId == _attemptId) {
        _showError(error);
      }
    }
  }

  void _resetToUserSelection({bool clearSelectedUser = false}) {
    _replace(
      _state.copyWith(
        authMode: AuthMode.userSelection,
        clearSelectedUser: clearSelectedUser,
        clearPrompt: true,
        clearSelectedSession: true,
        clearError: true,
        backendAuthState: BackendAuthState.idle,
      ),
    );
  }

  void _showError(Object error) {
    _replace(
      _state.copyWith(authMode: AuthMode.error, error: _getDisplayError(error)),
    );
  }

  void _replace(GreeterState next) {
    _state = next;
    notifyListeners();
  }

  String _getDisplayError(Object error) {
    if (error is GreeterGatewayException) {
      return error.message;
    }
    return 'The greeter service is unavailable.';
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    unawaited(_gateway.close());
    unawaited(_effects.close());
    super.dispose();
  }
}
