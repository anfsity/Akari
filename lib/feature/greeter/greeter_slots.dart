import 'greeter_state.dart';

/// Immutable semantic input consumed by Scene.
class GreeterSceneSlots {
  GreeterSceneSlots({
    required this.service,
    required this.auth,
    required this.userPicker,
    required this.sessionPicker,
    required this.power,
    required this.background,
  });

  factory GreeterSceneSlots.fromState(GreeterState state) {
    return GreeterSceneSlots(
      service: ServiceSlots(mode: state.serviceMode, error: state.serviceError),
      auth: AuthSlots(
        mode: state.authMode,
        selectedUser: state.selectedUser,
        prompt: state.prompt,
        error: state.authError,
      ),
      userPicker: UserPickerSlots(
        users: state.users,
        selected: state.selectedUser,
      ),
      sessionPicker: SessionPickerSlots(
        mode: state.catalogMode,
        sessions: state.sessions,
        selected: state.selectedSession,
        error: state.catalogError,
      ),
      power: PowerSlots(mode: state.powerMode, error: state.powerError),
      background: BackgroundSlots.fromAuthMode(state.authMode),
    );
  }

  final ServiceSlots service;
  final AuthSlots auth;
  final UserPickerSlots userPicker;
  final SessionPickerSlots sessionPicker;
  final PowerSlots power;
  final BackgroundSlots background;
}

class ServiceSlots {
  const ServiceSlots({required this.mode, required this.error});

  final ServiceMode mode;
  final GreeterError? error;
}

class AuthSlots {
  const AuthSlots({
    required this.mode,
    required this.selectedUser,
    required this.prompt,
    required this.error,
  });

  final AuthMode mode;
  final UserSummary? selectedUser;
  final PromptState? prompt;
  final GreeterError? error;
}

class UserPickerSlots {
  UserPickerSlots({required List<UserSummary> users, required this.selected})
    : users = List.unmodifiable(users);

  final List<UserSummary> users;
  final UserSummary? selected;
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
}

class PowerSlots {
  const PowerSlots({required this.mode, required this.error});

  final PowerMode mode;
  final GreeterError? error;
}

enum BackgroundMood { calm, active, success, error }

class BackgroundSlots {
  const BackgroundSlots({required this.mood, required this.intensity});

  factory BackgroundSlots.fromAuthMode(AuthMode mode) {
    final mood = switch (mode) {
      AuthMode.error => BackgroundMood.error,
      AuthMode.submitting || AuthMode.prompting => BackgroundMood.active,
      AuthMode.handingOff => BackgroundMood.success,
      _ => BackgroundMood.calm,
    };

    return BackgroundSlots(
      mood: mood,
      intensity: mood == BackgroundMood.calm ? 0.35 : 0.65,
    );
  }

  final BackgroundMood mood;
  final double intensity;
}
