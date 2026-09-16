import 'dart:async';

import '../greeter_state.dart';

sealed class GreeterEvent {
  const GreeterEvent();
}

class BackendStateChanged extends GreeterEvent {
  const BackendStateChanged({
    required this.attemptId,
    required this.state,
    required this.detail,
  });

  final String attemptId;
  final BackendAuthState state;
  final String detail;
}

class BackendPromptReceived extends GreeterEvent {
  const BackendPromptReceived({
    required this.attemptId,
    required this.kind,
    required this.text,
  });

  final String attemptId;
  final PromptKind kind;
  final String text;
}

class BackendDisconnected extends GreeterEvent {
  const BackendDisconnected();
}

class BackendStateSnapshot {
  const BackendStateSnapshot({required this.state, required this.detail});

  final BackendAuthState state;
  final String detail;
}

abstract interface class GreeterGateway {
  Stream<GreeterEvent> get events;

  Future<BackendStateSnapshot> getState();

  Future<List<UserSummary>> listUsers();

  Future<List<SessionSummary>> listSessions();

  Future<String> beginAuthentication(String username);

  Future<void> respond(String attemptId, String response);

  Future<void> cancel(String attemptId);

  Future<void> startSession(String attemptId, String sessionId);

  Future<void> powerAction(PowerAction action);

  Future<void> close();
}

class GreeterGatewayException implements Exception {
  const GreeterGatewayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Deterministic gateway used by widget tests and the no-bus preview.
///
/// The production implementation keeps this port unchanged while using
/// `io.mozais.Greeter1` over D-Bus.
class DemoGreeterGateway implements GreeterGateway {
  final StreamController<GreeterEvent> _events =
      StreamController<GreeterEvent>.broadcast();

  String? _attemptId;

  @override
  Stream<GreeterEvent> get events => _events.stream;

  @override
  Future<BackendStateSnapshot> getState() async {
    return BackendStateSnapshot(
      state: _attemptId == null
          ? BackendAuthState.idle
          : BackendAuthState.waitingForInput,
      detail: '',
    );
  }

  @override
  Future<List<UserSummary>> listUsers() async {
    return const [
      UserSummary(id: 'alice', displayName: 'Alice'),
      UserSummary(id: 'bob', displayName: 'Bob'),
    ];
  }

  @override
  Future<List<SessionSummary>> listSessions() async {
    return const [
      SessionSummary(id: 'wayland:sway', name: 'Sway'),
      SessionSummary(id: 'wayland:hyprland', name: 'Hyprland'),
    ];
  }

  @override
  Future<String> beginAuthentication(String username) async {
    final attemptId = 'demo-attempt-$username';
    _attemptId = attemptId;
    _events.add(
      BackendStateChanged(
        attemptId: attemptId,
        state: BackendAuthState.creatingSession,
        detail: '',
      ),
    );
    scheduleMicrotask(() {
      if (_attemptId == attemptId) {
        _events.add(
          BackendPromptReceived(
            attemptId: attemptId,
            kind: PromptKind.secret,
            text: 'Password',
          ),
        );
        _events.add(
          BackendStateChanged(
            attemptId: attemptId,
            state: BackendAuthState.waitingForInput,
            detail: '',
          ),
        );
      }
    });
    return attemptId;
  }

  @override
  Future<void> respond(String attemptId, String response) async {
    if (response.trim().isEmpty) {
      throw const GreeterGatewayException('A response is required.');
    }
    if (_attemptId == attemptId) {
      _events.add(
        BackendStateChanged(
          attemptId: attemptId,
          state: BackendAuthState.authenticated,
          detail: '',
        ),
      );
    }
  }

  @override
  Future<void> cancel(String attemptId) async {
    if (_attemptId == attemptId) {
      _attemptId = null;
      _events.add(
        BackendStateChanged(
          attemptId: attemptId,
          state: BackendAuthState.idle,
          detail: '',
        ),
      );
    }
  }

  @override
  Future<void> startSession(String attemptId, String sessionId) async {
    if (_attemptId == attemptId) {
      _events.add(
        BackendStateChanged(
          attemptId: attemptId,
          state: BackendAuthState.handingOff,
          detail: '',
        ),
      );
    }
  }

  @override
  Future<void> powerAction(PowerAction action) async {}

  @override
  Future<void> close() => _events.close();
}
