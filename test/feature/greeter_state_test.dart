import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_greeter/feature/greeter/greeter_state.dart';

void main() {
  test('GreeterState owns immutable user and session collections', () {
    final users = <UserSummary>[
      const UserSummary(id: 'alice', displayName: 'Alice'),
    ];
    final sessions = <SessionSummary>[
      const SessionSummary(id: 'sway', name: 'Sway'),
    ];

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
      () => state.sessions.add(
        const SessionSummary(id: 'hyprland', name: 'Hyprland'),
      ),
      throwsUnsupportedError,
    );
  });
}
