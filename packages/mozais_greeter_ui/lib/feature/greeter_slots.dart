import 'package:mozais_theme_sdk/mozais_theme_sdk.dart';

import 'greeter_state.dart';

export 'package:mozais_theme_sdk/mozais_theme_sdk.dart'
    show
        AccountPickerSlots,
        AuthPromptSlots,
        PowerSlots,
        ServiceSlots,
        SessionPickerSlots;

/// Immutable semantic input consumed by Scene.
class GreeterSceneSlots {
  GreeterSceneSlots({
    required this.service,
    required this.authPrompt,
    required this.accountPicker,
    required this.sessionPicker,
    required this.power,
  });

  factory GreeterSceneSlots.fromState(
    GreeterState state, {
    bool? canSelectUser,
  }) {
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
        canSelect: canSelectUser ?? (state.authMode == AuthMode.userSelection),
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
