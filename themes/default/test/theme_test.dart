import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:theme_default/theme.dart';

void main() {
  test('confirm arrow is visible only for active login actions', () {
    final condition = buildDefaultTheme().document.nodes
        .singleWhere((node) => node.id == 'primary_action')
        .visibleWhen!;

    for (final auth in [
      ScenePredicate.isUserSelection,
      ScenePredicate.isAuthPrompting,
      ScenePredicate.isAuthSubmitting,
      ScenePredicate.isSessionSelection,
      ScenePredicate.isHandingOff,
      ScenePredicate.isAuthError,
    ]) {
      expect(
        evaluateSceneCondition(condition, {auth}),
        [
          ScenePredicate.isAuthPrompting,
          ScenePredicate.isAuthSubmitting,
          ScenePredicate.isSessionSelection,
          ScenePredicate.isAuthError,
        ].contains(auth),
        reason: auth.name,
      );
      expect(
        evaluateSceneCondition(condition, {auth, ScenePredicate.isDormant}),
        isFalse,
        reason: '${auth.name} while dormant',
      );
    }
  });

  test('builds the default palette from its extracted seed', () {
    final warm = buildDefaultTheme(seed: const Color(0xffe53935));
    final cool = buildDefaultTheme(seed: const Color(0xff1e88e5));

    expect(
      warm.materialTheme.colorScheme.primary,
      isNot(cool.materialTheme.colorScheme.primary),
    );
    expect(
      warm.materialTheme.colorScheme.surfaceContainerHigh,
      isNot(cool.materialTheme.colorScheme.surfaceContainerHigh),
    );
  });
}
