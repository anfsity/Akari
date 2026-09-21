import 'package:flutter/foundation.dart';

import 'greeter_state.dart';

/// Immutable semantic input consumed by Scene.
class GreeterSceneSlots {
  GreeterSceneSlots({
    required this.service,
    required this.authPrompt,
    required this.accountPicker,
    required this.sessionPicker,
    required this.power,
  });

  factory GreeterSceneSlots.fromState(GreeterState state) {
    return GreeterSceneSlots(
      service: (mode: state.serviceMode, error: state.serviceError),
      authPrompt: (
        mode: state.authMode,
        selectedUser: state.authMode == AuthMode.userSelection
            ? null
            : state.selectedUser,
        prompt: state.prompt,
        error: state.authError,
        promptError: state.promptError,
      ),
      accountPicker: AccountPickerSlots(
        users: state.users,
        selected: state.selectedUser,
      ),
      sessionPicker: SessionPickerSlots(
        mode: state.catalogMode,
        sessions: state.sessions,
        selected: state.selectedSession,
        error: state.catalogError,
      ),
      power: (mode: state.powerMode, error: state.powerError),
    );
  }

  final ServiceSlots service;
  final AuthPromptSlots authPrompt;
  final AccountPickerSlots accountPicker;
  final SessionPickerSlots sessionPicker;
  final PowerSlots power;
}

typedef ServiceSlots = ({ServiceMode mode, GreeterError? error});

typedef AuthPromptSlots = ({
  AuthMode mode,
  UserSummary? selectedUser,
  PromptState? prompt,
  GreeterError? error,
  String? promptError,
});

class AccountPickerSlots {
  AccountPickerSlots({required List<UserSummary> users, required this.selected})
    : users = List.unmodifiable(users);

  final List<UserSummary> users;
  final UserSummary? selected;

  @override
  bool operator ==(Object other) {
    return other is AccountPickerSlots &&
        listEquals(other.users, users) &&
        other.selected == selected;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(users), selected);
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
