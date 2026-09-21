import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_greeter_ui/feature/greeter/greeter_slots.dart';
import 'package:mozais_greeter_ui/feature/greeter/greeter_state.dart';
import 'package:mozais_greeter_ui/scene/greeter_scene/greeter_scene_adapter.dart';
import 'package:mozais_scene/mozais_scene.dart';

void main() {
  test('maps dormant service, auth, session, and power state', () {
    final predicates = activeScenePredicates(
      service: (mode: ServiceMode.ready, error: null),
      auth: (
        mode: AuthMode.prompting,
        selectedUser: null,
        prompt: null,
        error: null,
        promptError: null,
      ),
      account: AccountPickerSlots(users: const [], selected: null),
      session: SessionPickerSlots(
        mode: CatalogMode.empty,
        sessions: const [],
        selected: null,
        error: null,
      ),
      power: (mode: PowerMode.idle, error: null),
      dormant: true,
    );

    expect(predicates, contains(ScenePredicate.isDormant));
    expect(predicates, contains(ScenePredicate.isServiceReady));
    expect(predicates, contains(ScenePredicate.isAuthPrompting));
    expect(predicates, contains(ScenePredicate.isSessionEmpty));
    expect(predicates, isNot(contains(ScenePredicate.isServiceStarting)));
    expect(predicates, isNot(contains(ScenePredicate.isServiceUnavailable)));
    expect(predicates, isNot(contains(ScenePredicate.hasSelectedUser)));
    expect(predicates, isNot(contains(ScenePredicate.isPowerExecuting)));
  });

  test('reports an executing power action and a selected account', () {
    final predicates = activeScenePredicates(
      service: (mode: ServiceMode.unavailable, error: null),
      auth: (
        mode: AuthMode.error,
        selectedUser: null,
        prompt: null,
        error: null,
        promptError: null,
      ),
      account: AccountPickerSlots(
        users: const [UserSummary(id: 'alice', displayName: 'Alice')],
        selected: const UserSummary(id: 'alice', displayName: 'Alice'),
      ),
      session: SessionPickerSlots(
        mode: CatalogMode.ready,
        sessions: const [(id: 'sway', name: 'Sway')],
        selected: null,
        error: null,
      ),
      power: (
        mode: PowerMode.executing,
        error: (kind: GreeterErrorKind.power, message: 'x', recovery: GreeterRecovery.reconnectService),
      ),
      dormant: false,
    );

    expect(predicates, contains(ScenePredicate.isServiceUnavailable));
    expect(predicates, contains(ScenePredicate.isAuthError));
    expect(predicates, contains(ScenePredicate.hasSelectedUser));
    expect(predicates, contains(ScenePredicate.isSessionReady));
    expect(predicates, contains(ScenePredicate.isPowerExecuting));
    expect(predicates, contains(ScenePredicate.hasPowerError));
    expect(predicates, isNot(contains(ScenePredicate.isDormant)));
  });
}
