import 'package:mozais_scene_codegen/builder.dart';
import 'package:test/test.dart';

void main() {
  test('generates a typed document from a valid scene', () {
    final generated = generateScene('''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "contain", "useSafeArea": true},
  "background": {"kind": "solid", "color": "#112233"},
  "nodes": [
    {
      "id": "action",
      "kind": "primaryAction",
      "rect": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2},
      "action": "beginAuthentication",
      "visibleWhen": {"any": ["isAuthPrompting", "isAuthError"]}
    }
  ]
}
''');

    expect(generated, contains('SceneDocument testSceneDocument'));
    expect(generated, contains('SceneNodeKind.primaryAction'));
    expect(generated, contains('SceneAction.beginAuthentication'));
    expect(
      generated,
      contains(
        'visibleWhen: const SceneAny(<SceneCondition>['
        'ScenePredicateCondition(ScenePredicate.isAuthPrompting), '
        'ScenePredicateCondition(ScenePredicate.isAuthError)])',
      ),
    );
  });

  test('generates a negated predicate condition', () {
    final generated = generateScene('''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "contain"},
  "background": {"kind": "solid"},
  "nodes": [
    {
      "id": "panel",
      "kind": "glassPanel",
      "rect": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2},
      "visibleWhen": {"not": "isDormant"}
    }
  ]
}
''');

    expect(
      generated,
      contains(
        'visibleWhen: const SceneNot('
        'ScenePredicateCondition(ScenePredicate.isDormant))',
      ),
    );
  });

  test('rejects an unknown predicate', () {
    expect(
      () => generateScene('''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "contain"},
  "background": {"kind": "solid"},
  "nodes": [
    {
      "id": "panel",
      "kind": "glassPanel",
      "rect": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2},
      "visibleWhen": "isNonsense"
    }
  ]
}
'''),
      throwsFormatException,
    );
  });

  test('rejects an empty condition list', () {
    expect(
      () => generateScene('''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "contain"},
  "background": {"kind": "solid"},
  "nodes": [
    {
      "id": "panel",
      "kind": "glassPanel",
      "rect": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2},
      "visibleWhen": {"any": []}
    }
  ]
}
'''),
      throwsFormatException,
    );
  });

  test('rejects duplicate node ids', () {
    expect(
      () => generateScene('''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "contain"},
  "background": {"kind": "solid"},
  "nodes": [
    {"id": "same", "kind": "decoration", "rect": {"x": 0.1, "y": 0.1, "width": 0.1, "height": 0.1}},
    {"id": "same", "kind": "decoration", "rect": {"x": 0.2, "y": 0.2, "width": 0.1, "height": 0.1}}
  ]
}
'''),
      throwsFormatException,
    );
  });
}
