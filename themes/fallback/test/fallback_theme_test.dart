import 'package:flutter_test/flutter_test.dart';
import 'package:theme_fallback/theme.dart';
import 'package:scene/scene.dart';

void main() {
  test('buildFallbackTheme produces a valid theme definition', () {
    final theme = buildFallbackTheme();
    expect(theme.id, 'fallback');
    expect(theme.document.canvas.fit, SceneCanvasFit.contain);
    expect(theme.bundle.backgrounds, contains(SceneBackgroundKind.image));
    expect(theme.bundle.backgrounds, contains(SceneBackgroundKind.solid));

    final primaryActionNode = theme.document.nodes.firstWhere(
      (n) => n.id == 'primary_action',
    );
    expect(primaryActionNode.visibleWhen, isNotNull);
    final condition = primaryActionNode.visibleWhen!;
    expect(condition, isA<SceneAll>());
    final all = condition as SceneAll;
    expect(all.conditions, hasLength(2));
    expect(
      all.conditions[0],
      const SceneNot(ScenePredicateCondition(ScenePredicate.isDormant)),
    );
    expect(
      all.conditions[1],
      const SceneAny([
        ScenePredicateCondition(ScenePredicate.isAuthPrompting),
        ScenePredicateCondition(ScenePredicate.isAuthSubmitting),
        ScenePredicateCondition(ScenePredicate.isSessionSelection),
        ScenePredicateCondition(ScenePredicate.isAuthError),
        ScenePredicateCondition(ScenePredicate.isServiceUnavailable),
      ]),
    );
  });
}
