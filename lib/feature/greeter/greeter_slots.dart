import 'package:flutter/foundation.dart';

import 'greeter_state.dart';

/// Immutable semantic input consumed by Scene.
class GreeterSceneSlots {
  GreeterSceneSlots({
    required this.service,
    required this.authPrompt,
    required this.accountPicker,
    required this.sessionPicker,
    required this.continueAction,
    required this.power,
  });

  factory GreeterSceneSlots.fromState(GreeterState state) {
    return GreeterSceneSlots(
      service: ServiceSlots(mode: state.serviceMode, error: state.serviceError),
      authPrompt: AuthPromptSlots(
        mode: state.authMode,
        selectedUser: state.authMode == AuthMode.userSelection
            ? null
            : state.selectedUser,
        prompt: state.prompt,
        error: state.authError,
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
      continueAction: ContinueSlots(
        enabled: state.selectedUser != null && state.selectedSession != null,
      ),
      power: PowerSlots(mode: state.powerMode, error: state.powerError),
    );
  }

  final ServiceSlots service;
  final AuthPromptSlots authPrompt;
  final AccountPickerSlots accountPicker;
  final SessionPickerSlots sessionPicker;
  final ContinueSlots continueAction;
  final PowerSlots power;
}

class ServiceSlots {
  const ServiceSlots({required this.mode, required this.error});

  final ServiceMode mode;
  final GreeterError? error;

  @override
  bool operator ==(Object other) {
    return other is ServiceSlots && other.mode == mode && other.error == error;
  }

  @override
  int get hashCode => Object.hash(mode, error);
}

class AuthPromptSlots {
  const AuthPromptSlots({
    required this.mode,
    required this.selectedUser,
    required this.prompt,
    required this.error,
  });

  final AuthMode mode;
  final UserSummary? selectedUser;
  final PromptState? prompt;
  final GreeterError? error;

  @override
  bool operator ==(Object other) {
    return other is AuthPromptSlots &&
        other.mode == mode &&
        other.selectedUser == selectedUser &&
        other.prompt == prompt &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(mode, selectedUser, prompt, error);
}

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

class ContinueSlots {
  const ContinueSlots({required this.enabled});

  final bool enabled;

  @override
  bool operator ==(Object other) {
    return other is ContinueSlots && other.enabled == enabled;
  }

  @override
  int get hashCode => enabled.hashCode;
}

class PowerSlots {
  const PowerSlots({required this.mode, required this.error});

  final PowerMode mode;
  final GreeterError? error;

  @override
  bool operator ==(Object other) {
    return other is PowerSlots && other.mode == mode && other.error == error;
  }

  @override
  int get hashCode => Object.hash(mode, error);
}
