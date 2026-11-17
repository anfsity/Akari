import 'package:theme_sdk/theme_sdk.dart';

enum StudioPreviewScenario {
  password('Password'),
  username('Username'),
  submitting('Signing in'),
  success('Entering desktop'),
  rejectedPassword('Wrong password'),
  error('Authentication error'),
  userSelection('Choose account'),
  sessionSelection('Choose session'),
  starting('Connecting'),
  unavailable('Service unavailable');

  const StudioPreviewScenario(this.label);
  final String label;
}

enum StudioTransition {
  entrance(
    'Entrance',
    false,
    false,
    StudioPreviewScenario.password,
    StudioPreviewScenario.password,
  ),
  wake(
    'Dormant → Login',
    true,
    false,
    StudioPreviewScenario.password,
    StudioPreviewScenario.password,
  ),
  sleep(
    'Login → Dormant',
    false,
    true,
    StudioPreviewScenario.password,
    StudioPreviewScenario.password,
  ),
  success(
    'Submit → Success',
    false,
    false,
    StudioPreviewScenario.submitting,
    StudioPreviewScenario.success,
  ),
  error(
    'Submit → Error',
    false,
    false,
    StudioPreviewScenario.submitting,
    StudioPreviewScenario.error,
  );

  const StudioTransition(
    this.label,
    this.fromDormant,
    this.toDormant,
    this.fromScenario,
    this.toScenario,
  );
  final String label;
  final bool fromDormant;
  final bool toDormant;
  final StudioPreviewScenario fromScenario;
  final StudioPreviewScenario toScenario;
}

String getScenePredicateLabel(ScenePredicate predicate) => switch (predicate) {
  ScenePredicate.isDormant => 'Dormant',
  ScenePredicate.isServiceStarting => 'Connecting',
  ScenePredicate.isServiceReady => 'Service ready',
  ScenePredicate.isServiceUnavailable => 'Service unavailable',
  ScenePredicate.isUserSelection => 'Choosing account',
  ScenePredicate.isAuthPrompting => 'Entering credentials',
  ScenePredicate.isAuthSubmitting => 'Authenticating',
  ScenePredicate.isSessionSelection => 'Choosing session',
  ScenePredicate.isHandingOff => 'Entering desktop',
  ScenePredicate.isAuthError => 'Authentication error',
  ScenePredicate.hasSelectedUser => 'Account selected',
  ScenePredicate.isSessionLoading => 'Loading sessions',
  ScenePredicate.isSessionReady => 'Sessions ready',
  ScenePredicate.isSessionEmpty => 'No sessions',
  ScenePredicate.isSessionFailed => 'Session error',
  ScenePredicate.isPowerExecuting => 'Power action running',
  ScenePredicate.hasPowerError => 'Power action error',
};
