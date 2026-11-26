import 'collections.dart';

/// Boolean questions about semantic greeter state used by [SceneCondition].
///
/// The vocabulary is closed so a theme or editor can only reference known
/// predicates; it never evaluates arbitrary expressions or backend values.
enum ScenePredicate {
  isDormant,
  isServiceStarting,
  isServiceReady,
  isServiceUnavailable,
  isUserSelection,
  isAuthPrompting,
  isAuthSubmitting,
  isSessionSelection,
  isHandingOff,
  isAuthError,
  hasSelectedUser,
  isSessionLoading,
  isSessionReady,
  isSessionEmpty,
  isSessionFailed,
  isPowerExecuting,
  hasPowerError,
}

/// Declarative presence condition over [ScenePredicate] values.
sealed class SceneCondition {
  const SceneCondition();
}

final class ScenePredicateCondition extends SceneCondition {
  const ScenePredicateCondition(this.predicate);

  final ScenePredicate predicate;

  @override
  bool operator ==(Object other) =>
      other is ScenePredicateCondition && other.predicate == predicate;

  @override
  int get hashCode => predicate.hashCode;
}

final class SceneAll extends SceneCondition {
  const SceneAll(this.conditions);

  final List<SceneCondition> conditions;

  @override
  bool operator ==(Object other) =>
      other is SceneAll && listEquals(other.conditions, conditions);

  @override
  int get hashCode => Object.hash(SceneAll, Object.hashAll(conditions));
}

final class SceneAny extends SceneCondition {
  const SceneAny(this.conditions);

  final List<SceneCondition> conditions;

  @override
  bool operator ==(Object other) =>
      other is SceneAny && listEquals(other.conditions, conditions);

  @override
  int get hashCode => Object.hash(SceneAny, Object.hashAll(conditions));
}

final class SceneNot extends SceneCondition {
  const SceneNot(this.condition);

  final SceneCondition condition;

  @override
  bool operator ==(Object other) =>
      other is SceneNot && other.condition == condition;

  @override
  int get hashCode => Object.hash(SceneNot, condition);
}

/// Evaluates [condition] against the predicates currently true for the scene.
bool evaluateSceneCondition(
  SceneCondition condition,
  Set<ScenePredicate> activePredicates,
) {
  return switch (condition) {
    ScenePredicateCondition(:final predicate) => activePredicates.contains(
      predicate,
    ),
    SceneAll(:final conditions) => conditions.every(
      (condition) => evaluateSceneCondition(condition, activePredicates),
    ),
    SceneAny(:final conditions) => conditions.any(
      (condition) => evaluateSceneCondition(condition, activePredicates),
    ),
    SceneNot(:final condition) => !evaluateSceneCondition(
      condition,
      activePredicates,
    ),
  };
}

/// Shared sign-in/recovery visibility rule used by the primary action slot.
const SceneCondition primaryActionVisibilityCondition = SceneAll([
  SceneNot(ScenePredicateCondition(ScenePredicate.isDormant)),
  SceneAny([
    ScenePredicateCondition(ScenePredicate.isAuthPrompting),
    ScenePredicateCondition(ScenePredicate.isAuthSubmitting),
    ScenePredicateCondition(ScenePredicate.isSessionSelection),
    ScenePredicateCondition(ScenePredicate.isAuthError),
    ScenePredicateCondition(ScenePredicate.isServiceUnavailable),
  ]),
]);
