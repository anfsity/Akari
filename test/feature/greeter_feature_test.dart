import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_greeter/feature/greeter/greeter_commands.dart';
import 'package:mozais_greeter/feature/greeter/greeter_effect.dart';
import 'package:mozais_greeter/feature/greeter/greeter_feature.dart';
import 'package:mozais_greeter/feature/greeter/greeter_state.dart';
import 'package:mozais_greeter/feature/greeter/ports/greeter_gateway.dart';
import 'package:mozais_greeter/feature/greeter/ports/session_store.dart';

void main() {
  test('initializes from the backend state snapshot', () async {
    final gateway = _FakeGreeterGateway();
    final feature = GreeterFeature(gateway: gateway);

    await feature.initialize();
    await _flushEvents();

    expect(gateway.getStateCalls, 1);
    expect(feature.state.serviceMode, ServiceMode.ready);
    expect(feature.state.backendAuthState, BackendAuthState.idle);
    expect(feature.state.authMode, AuthMode.userSelection);
    expect(feature.state.users, hasLength(2));
    expect(feature.state.catalogMode, CatalogMode.ready);
    expect(feature.state.sessions, hasLength(1));

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
      expect(feature.state.dormant, isFalse);
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
      await _flushEvents();

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
    await _flushEvents();
    await feature.dispatch(const WakeGreeterCommand());

    await _selectDefaultSession(feature);
    await feature.dispatch(SelectUserCommand(gateway.users.first));
    await _flushEvents();

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
    await _flushEvents();
    await feature.dispatch(const WakeGreeterCommand());

    await _selectDefaultSession(feature);
    await feature.dispatch(SelectUserCommand(gateway.users.first));
    await _flushEvents();
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

  test('power actions only update the power slot', () async {
    final gateway = _FakeGreeterGateway();
    final feature = await _createPromptedFeature(gateway);
    var authPromptChanges = 0;
    var powerChanges = 0;
    feature.authPromptSlots.addListener(() => authPromptChanges++);
    feature.powerSlots.addListener(() => powerChanges++);

    await feature.dispatch(
      const RequestPowerActionCommand(PowerAction.suspend),
    );

    expect(authPromptChanges, 0);
    expect(powerChanges, 2);
    expect(feature.powerSlots.value.mode, PowerMode.succeeded);

    feature.dispose();
  });

  test(
    'selecting an account begins authentication without touching sessions',
    () async {
      final gateway = _FakeGreeterGateway();
      final feature = GreeterFeature(gateway: gateway);
      await feature.initialize();
      await _flushEvents();
      await feature.dispatch(const WakeGreeterCommand());

      var accountChanges = 0;
      var sessionChanges = 0;
      feature.accountPickerSlots.addListener(() => accountChanges++);
      feature.sessionPickerSlots.addListener(() => sessionChanges++);

      // The default session is selected while the catalog loads.
      expect(feature.sessionPickerSlots.value.selected?.id, 'wayland:sway');

      await feature.dispatch(SelectUserCommand(gateway.users.first));
      await _flushEvents();

      expect(accountChanges, 1);
      expect(sessionChanges, 0);
      expect(feature.state.authMode, AuthMode.prompting);

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
    'loads the session catalog independently of account selection',
    () async {
      final gateway = _FakeGreeterGateway();
      final sessions = Completer<List<SessionSummary>>();
      gateway.sessionsFuture = sessions.future;
      final feature = GreeterFeature(gateway: gateway);
      await feature.initialize();

      expect(feature.state.catalogMode, CatalogMode.loading);
      expect(feature.state.authMode, AuthMode.userSelection);
      expect(gateway.listSessionsCalls, 1);

      await feature.dispatch(SelectUserCommand(gateway.users.first));
      expect(feature.state.selectedUser?.id, 'alice');
      expect(feature.state.authMode, AuthMode.userSelection);

      sessions.complete(const [(id: 'wayland:sway', name: 'Sway')]);
      await _flushEvents();

      expect(feature.state.catalogMode, CatalogMode.ready);
      await _selectDefaultSession(feature);
      expect(feature.state.selectedSession?.id, 'wayland:sway');

      feature.dispose();
    },
  );

  test('keeps authentication state when the session catalog fails', () async {
    final gateway = _FakeGreeterGateway();
    gateway.sessionsError = const GreeterGatewayException(
      'Session catalog unavailable.',
      kind: GreeterErrorKind.session,
    );
    final feature = GreeterFeature(gateway: gateway);
    await feature.initialize();
    await _flushEvents();

    expect(feature.state.catalogMode, CatalogMode.failed);
    expect(feature.state.catalogError?.kind, GreeterErrorKind.session);
    expect(
      feature.state.catalogError?.recovery,
      GreeterRecovery.retrySessionCatalog,
    );
    expect(feature.state.authMode, AuthMode.userSelection);
    expect(feature.state.backendAuthState, BackendAuthState.idle);
    expect(feature.state.authError, isNull);

    gateway.sessionsError = null;
    await feature.dispatch(const RetrySessionCatalogCommand());

    expect(feature.state.catalogMode, CatalogMode.ready);
    expect(feature.state.authMode, AuthMode.userSelection);
    expect(gateway.listSessionsCalls, 2);

    feature.dispose();
  });

  test('retries a failed session start with the selected session', () async {
    final gateway = _FakeGreeterGateway();
    final feature = await _createPromptedFeature(gateway);

    gateway.startSessionError = const GreeterGatewayException(
      'Session could not be started.',
      kind: GreeterErrorKind.session,
    );
    gateway.emit(
      const BackendStateChanged(
        attemptId: 'attempt-1',
        state: BackendAuthState.authenticated,
        detail: '',
      ),
    );
    await _flushEvents();

    expect(gateway.startSessionCalls, 1);
    expect(feature.state.authMode, AuthMode.sessionSelection);
    expect(feature.state.catalogMode, CatalogMode.ready);
    expect(feature.state.selectedSession?.id, 'wayland:sway');
    expect(feature.state.catalogError, isNull);

    gateway.startSessionError = null;
    await feature.dispatch(const StartSelectedSessionCommand());

    expect(gateway.startSessionCalls, 2);
    expect(feature.state.authMode, AuthMode.handingOff);

    feature.dispose();
  });

  test('allows choosing a session before choosing an account', () async {
    final gateway = _FakeGreeterGateway();
    final feature = GreeterFeature(gateway: gateway);
    await feature.initialize();
    await _flushEvents();
    await feature.dispatch(const WakeGreeterCommand());

    await _selectDefaultSession(feature);
    expect(feature.state.selectedSession?.id, 'wayland:sway');
    expect(feature.state.authMode, AuthMode.userSelection);

    await feature.dispatch(SelectUserCommand(gateway.users.first));
    expect(feature.state.selectedUser?.id, 'alice');

    await _flushEvents();
    expect(feature.state.authMode, AuthMode.prompting);

    feature.dispose();
  });
  test('auto-selects the only available account', () async {
    final gateway = _FakeGreeterGateway()
      ..users = const [UserSummary(id: 'alice', displayName: 'Alice')];
    final feature = GreeterFeature(gateway: gateway);
    await feature.initialize();
    await _flushEvents();

    expect(feature.state.selectedUser?.id, 'alice');

    feature.dispose();
  });

  test('prefers hyprland when no session was stored', () async {
    final gateway = _FakeGreeterGateway()
      ..sessionsFuture = Future.value(const [
        (id: 'wayland:sway', name: 'Sway'),
        (id: 'wayland:hyprland', name: 'Hyprland'),
      ]);
    final feature = GreeterFeature(gateway: gateway);
    await feature.initialize();
    await _flushEvents();

    expect(feature.state.selectedSession?.id, 'wayland:hyprland');

    feature.dispose();
  });

  test('restores and saves the selected session', () async {
    final store = _FakeSessionStore()..storedId = 'wayland:sway';
    final gateway = _FakeGreeterGateway()
      ..sessionsFuture = Future.value(const [
        (id: 'wayland:sway', name: 'Sway'),
        (id: 'wayland:hyprland', name: 'Hyprland'),
      ]);
    final feature = GreeterFeature(gateway: gateway, sessionStore: store);
    await feature.initialize();
    await _flushEvents();

    expect(feature.state.selectedSession?.id, 'wayland:sway');

    await feature.dispatch(
      const SelectSessionCommand((id: 'wayland:hyprland', name: 'Hyprland')),
    );
    await _flushEvents();

    expect(store.savedIds, ['wayland:hyprland']);

    feature.dispose();
  });

  test('starts dormant and toggles on wake and sleep', () async {
    final gateway = _FakeGreeterGateway();
    final feature = GreeterFeature(gateway: gateway);
    await feature.initialize();
    await _flushEvents();

    expect(feature.state.dormant, isTrue);

    await feature.dispatch(const WakeGreeterCommand());
    expect(feature.state.dormant, isFalse);

    await feature.dispatch(const SleepGreeterCommand());
    expect(feature.state.dormant, isTrue);

    feature.dispose();
  });

  test('sleeping cancels the active authentication attempt', () async {
    final gateway = _FakeGreeterGateway();
    final feature = await _createPromptedFeature(gateway);
    expect(feature.state.authMode, AuthMode.prompting);

    await feature.dispatch(const SleepGreeterCommand());
    await _flushEvents();

    expect(feature.state.dormant, isTrue);
    expect(feature.state.authMode, AuthMode.userSelection);
    expect(feature.state.prompt, isNull);
    expect(gateway.cancelledAttemptId, 'attempt-1');

    feature.dispose();
  });
}

Future<GreeterFeature> _createPromptedFeature(
  _FakeGreeterGateway gateway,
) async {
  final feature = GreeterFeature(gateway: gateway);
  await feature.initialize();
  await _flushEvents();
  await feature.dispatch(const WakeGreeterCommand());
  await _selectDefaultSession(feature);
  await feature.dispatch(SelectUserCommand(gateway.users.first));
  await _flushEvents();
  return feature;
}

Future<void> _selectDefaultSession(GreeterFeature feature) async {
  await feature.dispatch(
    const SelectSessionCommand((id: 'wayland:sway', name: 'Sway')),
  );
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeSessionStore implements SessionStore {
  String? storedId;
  final List<String> savedIds = [];

  @override
  Future<String?> readSelectedSessionId() async => storedId;

  @override
  Future<void> saveSelectedSessionId(String sessionId) async {
    savedIds.add(sessionId);
    storedId = sessionId;
  }
}

class _FakeGreeterGateway implements GreeterGateway {
  final StreamController<GreeterEvent> _events =
      StreamController<GreeterEvent>.broadcast();

  List<UserSummary> users = const <UserSummary>[
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
    return const [(id: 'wayland:sway', name: 'Sway')];
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
