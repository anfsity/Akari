import 'package:flutter/foundation.dart';

import 'greeter_models.dart';

typedef ServiceSlots = ({ServiceMode mode, GreeterError? error});

typedef AuthPromptSlots = ({
  AuthMode mode,
  UserSummary? selectedUser,
  PromptState? prompt,
  GreeterError? error,
  String? promptError,
});

class AccountPickerSlots {
  AccountPickerSlots({
    required List<UserSummary> users,
    required this.selected,
    this.canSelect = false,
  }) : users = List.unmodifiable(users);

  final List<UserSummary> users;
  final UserSummary? selected;
  final bool canSelect;

  @override
  bool operator ==(Object other) {
    return other is AccountPickerSlots &&
        listEquals(other.users, users) &&
        other.selected == selected &&
        other.canSelect == canSelect;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(users), selected, canSelect);
}

class SessionPickerSlots {
  SessionPickerSlots({
    required this.mode,
    required List<SessionSummary> sessions,
    required this.selected,
    required this.error,
  }) : sessions = List.unmodifiable(sessions);

  final CatalogMode mode;
  final List<SessionSummary> sessions;
  final SessionSummary? selected;
  final GreeterError? error;

  @override
  bool operator ==(Object other) {
    return other is SessionPickerSlots &&
        other.mode == mode &&
        listEquals(other.sessions, sessions) &&
        other.selected == selected &&
        other.error == error;
  }

  @override
  int get hashCode =>
      Object.hash(mode, Object.hashAll(sessions), selected, error);
}

typedef PowerSlots = ({PowerMode mode, GreeterError? error});
