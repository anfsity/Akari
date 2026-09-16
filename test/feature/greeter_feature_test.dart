import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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

  test('applies queued prompts and ignores stale events', () async {
    final gateway = _FakeGreeterGateway();
    final feature = GreeterFeature(gateway: gateway);
    final effects = <FeatureEffect>[];
    final effectSubscription = feature.effects.listen(effects.add);
    await feature.initialize();

    feature.selectUser(gateway.users.first);
    await feature.beginAuthentication();
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

    feature.selectUser(gateway.users.first);
    await feature.beginAuthentication();
    await Future<void>.delayed(Duration.zero);
    await feature.cancelAuthentication();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.cancelledAttemptId, 'attempt-1');
    expect(feature.state.authMode, AuthMode.userSelection);
    expect(feature.state.selectedUser, isNull);
    expect(feature.state.prompt, isNull);

    feature.dispose();
  });
}

class _FakeGreeterGateway implements GreeterGateway {
  final StreamController<GreeterEvent> _events =
      StreamController<GreeterEvent>.broadcast();

  final users = const <UserSummary>[
    UserSummary(id: 'alice', displayName: 'Alice'),
    UserSummary(id: 'bob', displayName: 'Bob'),
  ];

  int getStateCalls = 0;
  String? attemptId;
  String? cancelledAttemptId;

  @override
  Stream<GreeterEvent> get events => _events.stream;

  @override
  Future<BackendStateSnapshot> getState() async {
    getStateCalls++;
    return const BackendStateSnapshot(state: BackendAuthState.idle, detail: '');
  }

  @override
  Future<List<UserSummary>> listUsers() async => users;

  @override
  Future<List<SessionSummary>> listSessions() async => const [
    SessionSummary(id: 'wayland:sway', name: 'Sway'),
  ];

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
  Future<void> respond(String attemptId, String response) async {}

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
  Future<void> startSession(String attemptId, String sessionId) async {}

  @override
  Future<void> powerAction(PowerAction action) async {}

  void emit(GreeterEvent event) => _events.add(event);

  @override
  Future<void> close() => _events.close();
}
