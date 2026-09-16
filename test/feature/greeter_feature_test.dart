import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_greeter/feature/greeter/greeter_commands.dart';
import 'package:mozais_greeter/feature/greeter/greeter_effect.dart';
import 'package:mozais_greeter/feature/greeter/greeter_feature.dart';
import 'package:mozais_greeter/feature/greeter/greeter_state.dart';
import 'package:mozais_greeter/feature/greeter/ports/greeter_gateway.dart';

void main() {
  test('initializes from the backend state snapshot', () async {
    final gateway = _FakeGreeterGateway();
    final feature = GreeterFeature(gateway: gateway);

    await feature.initialize();

    expect(gateway.getStateCalls, 1);
    expect(feature.state.serviceMode, ServiceMode.ready);
    expect(feature.state.backendAuthState, BackendAuthState.idle);
    expect(feature.state.authMode, AuthMode.userSelection);
    expect(feature.state.users, hasLength(2));

    feature.dispose();
  });

  test(
    'maps an active backend snapshot to service reconnect recovery',
    () async {
      final gateway = _FakeGreeterGateway()
        ..snapshot = const BackendStateSnapshot(
          state: BackendAuthState.waitingForInput,
          detail: 'An authentication transaction is already active.',
        );
      final feature = GreeterFeature(gateway: gateway);

      await feature.initialize();

      expect(feature.state.serviceMode, ServiceMode.ready);
      expect(feature.state.authMode, AuthMode.error);
      expect(feature.state.authError?.kind, GreeterErrorKind.authentication);
      expect(
        feature.state.authError?.recovery,
        GreeterRecovery.reconnectService,
      );

      gateway.snapshot = const BackendStateSnapshot(
        state: BackendAuthState.idle,
        detail: '',
      );
      await feature.dispatch(const ReconnectServiceCommand());

      expect(gateway.getStateCalls, 2);
      expect(feature.state.serviceMode, ServiceMode.ready);
      expect(feature.state.authMode, AuthMode.userSelection);
      expect(feature.state.authError, isNull);

      feature.dispose();
    },
  );

  test('applies queued prompts and ignores stale events', () async {
    final gateway = _FakeGreeterGateway();
    final feature = GreeterFeature(gateway: gateway);
    final effects = <FeatureEffect>[];
    final effectSubscription = feature.effects.listen(effects.add);
    await feature.initialize();

    await feature.dispatch(SelectUserCommand(gateway.users.first));
    await feature.dispatch(const BeginAuthenticationCommand());
    await Future<void>.delayed(Duration.zero);

    expect(feature.state.authMode, AuthMode.prompting);
    expect(feature.state.prompt?.kind, PromptKind.secret);
    expect(effects.whereType<RequestFocusEffect>(), hasLength(1));

    gateway.emit(
      const BackendPromptReceived(
        attemptId: 'stale-attempt',
        kind: PromptKind.visible,
        text: 'stale',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(feature.state.prompt?.text, 'Password');

    gateway.emit(
      BackendPromptReceived(
        attemptId: gateway.attemptId!,
        kind: PromptKind.info,
        text: 'Authentication is continuing.',
      ),
    );
    gateway.emit(
      BackendPromptReceived(
        attemptId: gateway.attemptId!,
        kind: PromptKind.error,
        text: 'The provider is unavailable.',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      effects.whereType<ShowNoticeEffect>().map((effect) => effect.message),
      containsAll(<String>[
        'Authentication is continuing.',
        'The provider is unavailable.',
      ]),
    );
    expect(effects.whereType<ShowNoticeEffect>().last.isError, isTrue);

    gateway.emit(
      BackendPromptReceived(
        attemptId: gateway.attemptId!,
        kind: PromptKind.visible,
        text: 'One-time code',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(feature.state.prompt?.text, 'One-time code');

    await effectSubscription.cancel();
    feature.dispose();
  });

  test('cancelling clears the current attempt and prompt', () async {
    final gateway = _FakeGreeterGateway();
    final feature = GreeterFeature(gateway: gateway);
    await feature.initialize();

    await feature.dispatch(SelectUserCommand(gateway.users.first));
    await feature.dispatch(const BeginAuthenticationCommand());
    await Future<void>.delayed(Duration.zero);
    await feature.dispatch(const CancelAuthenticationCommand());
    await Future<void>.delayed(Duration.zero);

    expect(gateway.cancelledAttemptId, 'attempt-1');
    expect(feature.state.authMode, AuthMode.userSelection);
    expect(feature.state.selectedUser, isNull);
    expect(feature.state.prompt, isNull);

    feature.dispose();
  });

  test(
    'dispatches power actions without changing authentication state',
    () async {
      final gateway = _FakeGreeterGateway();
      final feature = await _createPromptedFeature(gateway);
      gateway.powerActionError = const GreeterGatewayException(
        'Power action denied.',
        kind: GreeterErrorKind.power,
      );

      await feature.dispatch(
        const RequestPowerActionCommand(PowerAction.suspend),
      );

      expect(gateway.requestedPowerAction, PowerAction.suspend);
      expect(feature.state.powerMode, PowerMode.failed);
      expect(feature.state.powerError?.kind, GreeterErrorKind.power);
      expect(feature.state.authMode, AuthMode.prompting);
      expect(feature.state.authError, isNull);
      expect(feature.state.backendAuthState, BackendAuthState.waitingForInput);

      feature.dispose();
    },
  );

  test('rejects a blank prompt response without calling the gateway', () async {
    final gateway = _FakeGreeterGateway();
    final feature = await _createPromptedFeature(gateway);

    await feature.dispatch(const RespondToPromptCommand('   '));

    expect(gateway.respondCalls, 0);
    expect(feature.state.authMode, AuthMode.error);
    expect(feature.state.authError?.kind, GreeterErrorKind.input);
    expect(feature.state.authError?.recovery, GreeterRecovery.retryPrompt);

    await feature.dispatch(const RetryPromptCommand());

    expect(feature.state.authMode, AuthMode.prompting);
    expect(feature.state.authError, isNull);

    feature.dispose();
  });

  test(
    'keeps authentication state while the session catalog is loading',
    () async {
      final gateway = _FakeGreeterGateway();
      final sessions = Completer<List<SessionSummary>>();
      gateway.sessionsFuture = sessions.future;
      final feature = await _createPromptedFeature(gateway);

      gateway.emit(
        const BackendStateChanged(
          attemptId: 'attempt-1',
          state: BackendAuthState.authenticated,
          detail: '',
        ),
      );
      await _flushEvents();

      expect(feature.state.catalogMode, CatalogMode.loading);
      expect(feature.state.authMode, AuthMode.sessionSelection);
      expect(feature.state.backendAuthState, BackendAuthState.authenticated);
      expect(feature.state.authError, isNull);
      expect(gateway.listSessionsCalls, 1);

      sessions.complete(const [
        SessionSummary(id: 'wayland:sway', name: 'Sway'),
      ]);
      await _flushEvents();

      expect(feature.state.catalogMode, CatalogMode.ready);
      expect(feature.state.authMode, AuthMode.sessionSelection);
      expect(feature.state.backendAuthState, BackendAuthState.authenticated);

      feature.dispose();
    },
  );

  test('keeps authentication state when the session catalog fails', () async {
    final gateway = _FakeGreeterGateway();
    gateway.sessionsError = const GreeterGatewayException(
      'Session catalog unavailable.',
      kind: GreeterErrorKind.session,
    );
    final feature = await _createPromptedFeature(gateway);

    gateway.emit(
      const BackendStateChanged(
        attemptId: 'attempt-1',
        state: BackendAuthState.authenticated,
        detail: '',
      ),
    );
    await _flushEvents();

    expect(feature.state.catalogMode, CatalogMode.failed);
    expect(feature.state.catalogError?.kind, GreeterErrorKind.session);
    expect(
      feature.state.catalogError?.recovery,
      GreeterRecovery.retrySessionCatalog,
    );
    expect(feature.state.authMode, AuthMode.sessionSelection);
    expect(feature.state.backendAuthState, BackendAuthState.authenticated);
    expect(feature.state.authError, isNull);

    gateway.sessionsError = null;
    await feature.dispatch(const RetrySessionCatalogCommand());

    expect(feature.state.catalogMode, CatalogMode.ready);
    expect(feature.state.authMode, AuthMode.sessionSelection);
    expect(gateway.listSessionsCalls, 2);

    feature.dispose();
  });

  test('retries a failed session start with the selected session', () async {
    final gateway = _FakeGreeterGateway();
    final feature = await _createPromptedFeature(gateway);

    gateway.emit(
      const BackendStateChanged(
        attemptId: 'attempt-1',
        state: BackendAuthState.authenticated,
        detail: '',
      ),
    );
    await _flushEvents();
    await feature.dispatch(
      const SelectSessionCommand(
        SessionSummary(id: 'wayland:sway', name: 'Sway'),
      ),
    );

    gateway.startSessionError = const GreeterGatewayException(
      'Session could not be started.',
      kind: GreeterErrorKind.session,
    );
    await feature.dispatch(const StartSelectedSessionCommand());

    expect(gateway.startSessionCalls, 1);
    expect(feature.state.authMode, AuthMode.sessionSelection);
    expect(feature.state.catalogMode, CatalogMode.failed);
    expect(feature.state.selectedSession?.id, 'wayland:sway');
    expect(feature.state.catalogError?.kind, GreeterErrorKind.session);
    expect(feature.state.catalogError?.recovery, GreeterRecovery.selectSession);

    gateway.startSessionError = null;
    await feature.dispatch(const StartSelectedSessionCommand());

    expect(gateway.startSessionCalls, 2);
    expect(feature.state.authMode, AuthMode.handingOff);

    feature.dispose();
  });
}

Future<GreeterFeature> _createPromptedFeature(
  _FakeGreeterGateway gateway,
) async {
  final feature = GreeterFeature(gateway: gateway);
  await feature.initialize();
  await feature.dispatch(SelectUserCommand(gateway.users.first));
  await feature.dispatch(const BeginAuthenticationCommand());
  await _flushEvents();
  return feature;
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeGreeterGateway implements GreeterGateway {
  final StreamController<GreeterEvent> _events =
      StreamController<GreeterEvent>.broadcast();

  final users = const <UserSummary>[
    UserSummary(id: 'alice', displayName: 'Alice'),
    UserSummary(id: 'bob', displayName: 'Bob'),
  ];

  int getStateCalls = 0;
  int listSessionsCalls = 0;
  int respondCalls = 0;
  String? attemptId;
  String? cancelledAttemptId;
  PowerAction? requestedPowerAction;
  Future<List<SessionSummary>>? sessionsFuture;
  Object? sessionsError;
  Object? powerActionError;
  Object? startSessionError;
  int startSessionCalls = 0;
  BackendStateSnapshot snapshot = const BackendStateSnapshot(
    state: BackendAuthState.idle,
    detail: '',
  );

  @override
  Stream<GreeterEvent> get events => _events.stream;

  @override
  Future<BackendStateSnapshot> getState() async {
    getStateCalls++;
    return snapshot;
  }

  @override
  Future<List<UserSummary>> listUsers() async => users;

  @override
  Future<List<SessionSummary>> listSessions() async {
    listSessionsCalls++;
    final future = sessionsFuture;
    if (future != null) {
      return future;
    }
    final error = sessionsError;
    if (error != null) {
      throw error;
    }
    return const [SessionSummary(id: 'wayland:sway', name: 'Sway')];
  }

  @override
  Future<String> beginAuthentication(String username) async {
    attemptId = 'attempt-1';
    _events.add(
      const BackendStateChanged(
        attemptId: 'attempt-1',
        state: BackendAuthState.creatingSession,
        detail: '',
      ),
    );
    _events.add(
      const BackendPromptReceived(
        attemptId: 'attempt-1',
        kind: PromptKind.secret,
        text: 'Password',
      ),
    );
    _events.add(
      const BackendStateChanged(
        attemptId: 'attempt-1',
        state: BackendAuthState.waitingForInput,
        detail: '',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    return attemptId!;
  }

  @override
  Future<void> respond(String attemptId, String response) async {
    respondCalls++;
  }

  @override
  Future<void> cancel(String attemptId) async {
    cancelledAttemptId = attemptId;
    _events.add(
      BackendStateChanged(
        attemptId: attemptId,
        state: BackendAuthState.idle,
        detail: '',
      ),
    );
  }

  @override
  Future<void> startSession(String attemptId, String sessionId) async {
    startSessionCalls++;
    final error = startSessionError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> powerAction(PowerAction action) async {
    requestedPowerAction = action;
    final error = powerActionError;
    if (error != null) {
      throw error;
    }
  }

  void emit(GreeterEvent event) => _events.add(event);

  @override
  Future<void> close() => _events.close();
}
