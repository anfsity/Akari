import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene/mozais_scene.dart';

void main() {
  test('a predicate condition matches only active predicates', () {
    const condition = ScenePredicateCondition(ScenePredicate.isDormant);

    expect(
      evaluateSceneCondition(condition, {ScenePredicate.isDormant}),
      isTrue,
    );
    expect(evaluateSceneCondition(condition, const {}), isFalse);
  });

  test('all requires every child', () {
    const condition = SceneAll([
      ScenePredicateCondition(ScenePredicate.isServiceReady),
      ScenePredicateCondition(ScenePredicate.hasSelectedUser),
    ]);

    expect(
      evaluateSceneCondition(condition, {
        ScenePredicate.isServiceReady,
        ScenePredicate.hasSelectedUser,
      }),
      isTrue,
    );
    expect(
      evaluateSceneCondition(condition, {ScenePredicate.isServiceReady}),
      isFalse,
    );
  });

  test('any requires at least one child', () {
    const condition = SceneAny([
      ScenePredicateCondition(ScenePredicate.isAuthPrompting),
      ScenePredicateCondition(ScenePredicate.isAuthError),
    ]);

    expect(
      evaluateSceneCondition(condition, {ScenePredicate.isAuthError}),
      isTrue,
    );
    expect(evaluateSceneCondition(condition, const {}), isFalse);
  });

  test('not inverts its child', () {
    const condition = SceneNot(
      ScenePredicateCondition(ScenePredicate.isDormant),
    );

    expect(evaluateSceneCondition(condition, const {}), isTrue);
    expect(
      evaluateSceneCondition(condition, {ScenePredicate.isDormant}),
      isFalse,
    );
  });

  test('nested conditions compose', () {
    const condition = SceneAll([
      SceneNot(ScenePredicateCondition(ScenePredicate.isDormant)),
      SceneAny([
        ScenePredicateCondition(ScenePredicate.isAuthPrompting),
        ScenePredicateCondition(ScenePredicate.isAuthSubmitting),
      ]),
    ]);

    expect(
      evaluateSceneCondition(condition, {ScenePredicate.isAuthPrompting}),
      isTrue,
    );
    expect(
      evaluateSceneCondition(condition, {
        ScenePredicate.isDormant,
        ScenePredicate.isAuthPrompting,
      }),
      isFalse,
    );
  });
}
