import 'greeter_state.dart';

/// Immutable semantic input consumed by Scene.
class GreeterSceneSlots {
  GreeterSceneSlots({
    required this.service,
    required this.auth,
    required List<UserSummary> users,
    required List<SessionSummary> sessions,
    required this.power,
    required this.background,
  }) : users = List.unmodifiable(users),
       sessions = List.unmodifiable(sessions);

  factory GreeterSceneSlots.fromState(GreeterState state) {
    return GreeterSceneSlots(
      service: ServiceSlots(state.serviceMode),
      auth: AuthSlots(
        mode: state.authMode,
        selectedUser: state.selectedUser,
        selectedSession: state.selectedSession,
        prompt: state.prompt,
        error: state.error,
      ),
      users: state.users,
      sessions: state.sessions,
      power: PowerSlots(state.powerMode),
      background: BackgroundSlots.fromAuthMode(state.authMode),
    );
  }

  final ServiceSlots service;
  final AuthSlots auth;
  final List<UserSummary> users;
  final List<SessionSummary> sessions;
  final PowerSlots power;
  final BackgroundSlots background;
}

class ServiceSlots {
  const ServiceSlots(this.mode);

  final ServiceMode mode;
}

class AuthSlots {
  const AuthSlots({
    required this.mode,
    required this.selectedUser,
    required this.selectedSession,
    required this.prompt,
    required this.error,
  });

  final AuthMode mode;
  final UserSummary? selectedUser;
  final SessionSummary? selectedSession;
  final PromptState? prompt;
  final String? error;
}

class PowerSlots {
  const PowerSlots(this.mode);

  final PowerMode mode;
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
