import 'package:flutter_test/flutter_test.dart';
import 'package:greeter_ui/feature/greeter_state.dart';

void main() {
  test('GreeterState owns immutable user and session collections', () {
    final users = <UserSummary>[
      const UserSummary(id: 'alice', displayName: 'Alice'),
    ];
    final sessions = <SessionSummary>[const (id: 'sway', name: 'Sway')];

    final state = GreeterState.initial().copyWith(
      users: users,
      sessions: sessions,
    );
    users.clear();
    sessions.clear();

    expect(state.users, hasLength(1));
    expect(state.sessions, hasLength(1));
    expect(
      () => state.users.add(const UserSummary(id: 'bob', displayName: 'Bob')),
      throwsUnsupportedError,
    );
    expect(
      () => state.sessions.add(const (id: 'hyprland', name: 'Hyprland')),
      throwsUnsupportedError,
    );
  });

  test('copyWith distinguishes omitted updates from explicit null resets', () {
    final populated = GreeterState.initial().copyWith(
      selectedUser: const UserSummary(id: 'alice', displayName: 'Alice'),
      selectedSession: const (id: 'sway', name: 'Sway'),
      prompt: const (kind: PromptKind.secret, text: 'Password'),
      promptError: 'Wrong password',
      authError: const (
        kind: GreeterErrorKind.authentication,
        message: 'Failed',
        recovery: GreeterRecovery.retryAuthentication,
      ),
      serviceError: const (
        kind: GreeterErrorKind.transport,
        message: 'Unavailable',
        recovery: GreeterRecovery.reconnectService,
      ),
      catalogError: const (
        kind: GreeterErrorKind.session,
        message: 'No sessions',
        recovery: GreeterRecovery.retrySessionCatalog,
      ),
      powerError: const (
        kind: GreeterErrorKind.power,
        message: 'Cannot sleep',
        recovery: GreeterRecovery.selectUser,
      ),
    );

    // Omitted parameters preserve existing values
    final preserved = populated.copyWith(dormant: false);
    expect(preserved.selectedUser?.id, 'alice');
    expect(preserved.selectedSession?.id, 'sway');
    expect(preserved.prompt?.text, 'Password');
    expect(preserved.promptError, 'Wrong password');
    expect(preserved.authError?.message, 'Failed');
    expect(preserved.serviceError?.message, 'Unavailable');
    expect(preserved.catalogError?.message, 'No sessions');
    expect(preserved.powerError?.message, 'Cannot sleep');
    expect(preserved.dormant, isFalse);

    // Explicit null clears the fields
    final cleared = populated.copyWith(
      selectedUser: null,
      selectedSession: null,
      prompt: null,
      promptError: null,
      authError: null,
      serviceError: null,
      catalogError: null,
      powerError: null,
    );
    expect(cleared.selectedUser, isNull);
    expect(cleared.selectedSession, isNull);
    expect(cleared.prompt, isNull);
    expect(cleared.promptError, isNull);
    expect(cleared.authError, isNull);
    expect(cleared.serviceError, isNull);
    expect(cleared.catalogError, isNull);
    expect(cleared.powerError, isNull);
  });
}
