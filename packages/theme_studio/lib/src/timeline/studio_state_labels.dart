import 'package:theme_sdk/theme_sdk.dart';

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
