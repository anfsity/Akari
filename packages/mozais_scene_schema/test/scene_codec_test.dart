import 'package:mozais_scene_schema/mozais_scene_schema.dart';
import 'package:test/test.dart';

const _scene = '''
{
  "id": "test",
  "version": 1,
  "canvas": {
    "fit": "contain",
    "useSafeArea": true,
    "referenceWidth": 2560,
    "referenceHeight": 1440
  },
  "background": {"kind": "solid", "color": "#112233"},
  "nodes": [
    {
      "id": "action",
      "kind": "primaryAction",
      "rect": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4},
      "transform": {"rotationZ": 12.5, "pivotX": 0.4},
      "z": 2,
      "motion": "fadeSlide",
      "action": "beginAuthentication",
      "visibleWhen": {"any": ["isAuthPrompting", "isAuthError"]},
      "properties": {"variant": "compact"}
    }
  ]
}
''';

void main() {
  test('decodes every field of a scene document', () {
    final document = decodeSceneDocument(_scene);

    expect(document.id, 'test');
    expect(document.version, 1);
    expect(document.canvas.fit, SceneCanvasFit.contain);
    expect(document.canvas.useSafeArea, isTrue);
    expect(document.canvas.referenceWidth, 2560);
    expect(document.canvas.referenceHeight, 1440);
    expect(document.background.kind, SceneBackgroundKind.solid);
    expect(document.background.color, 0xff112233);

    final node = document.nodes.single;
    expect(node.id, 'action');
    expect(node.kind, SceneNodeKind.primaryAction);
    expect(node.rect.x, 0.1);
    expect(node.rect.height, 0.4);
    expect(node.transform.rotationZ, 12.5);
    expect(node.transform.pivotX, 0.4);
    expect(node.transform.scaleX, 1);
    expect(node.z, 2);
    expect(node.motion, SceneMotionPreset.fadeSlide);
    expect(node.action, SceneAction.beginAuthentication);
    expect(node.properties, {'variant': 'compact'});
    final visibleWhen = node.visibleWhen;
    expect(visibleWhen, isA<SceneAny>());
    expect(
      (visibleWhen! as SceneAny).conditions.map(
        (child) => (child as ScenePredicateCondition).predicate,
      ),
      [ScenePredicate.isAuthPrompting, ScenePredicate.isAuthError],
    );
  });

  test('applies defaults for omitted optional fields', () {
    final document = decodeSceneDocument('''
{
  "id": "minimal",
  "version": 1,
  "canvas": {"fit": "cover"},
  "background": {"kind": "solid"},
  "nodes": [
    {
      "id": "panel",
      "kind": "glassPanel",
      "rect": {"x": 0, "y": 0, "width": 1, "height": 1}
    }
  ]
}
''');

    expect(document.canvas.useSafeArea, isTrue);
    expect(document.canvas.referenceWidth, 1920);
    expect(document.canvas.referenceHeight, 1080);
    expect(document.background.color, 0xff0d151a);
    expect(document.background.scrimOpacity, 0.35);

    final node = document.nodes.single;
    expect(node.transform.isIdentity, isTrue);
    expect(node.motion, SceneMotionPreset.none);
    expect(node.visibleWhen, isNull);
    expect(node.action, isNull);
    expect(node.properties, isEmpty);
  });

  test('round-trips through encode and decode', () {
    final document = decodeSceneDocument(_scene);
    final encoded = encodeSceneDocument(document);
    final reencoded = encodeSceneDocument(decodeSceneDocument(encoded));

    expect(reencoded, encoded);
  });

  test('encodes a negated predicate condition as a string leaf', () {
    const document = SceneDocument(
      id: 'test',
      version: 1,
      canvas: SceneCanvas(),
      background: SceneBackground(kind: SceneBackgroundKind.solid),
      nodes: [
        SceneNode(
          id: 'panel',
          kind: SceneNodeKind.glassPanel,
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
          visibleWhen: SceneNot(
            ScenePredicateCondition(ScenePredicate.isDormant),
          ),
        ),
      ],
    );

    final map = sceneDocumentToMap(document);
    expect(
      (map['nodes'] as List).single['visibleWhen'],
      {'not': 'isDormant'},
    );
  });

  test('rejects an unknown predicate', () {
    expect(
      () => decodeSceneDocument('''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "cover"},
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
      () => decodeSceneDocument('''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "cover"},
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
      () => decodeSceneDocument('''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "cover"},
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

  test('rejects a non-normalized rect', () {
    expect(
      () => decodeSceneDocument('''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "cover"},
  "background": {"kind": "solid"},
  "nodes": [
    {"id": "wide", "kind": "decoration", "rect": {"x": 0.5, "y": 0.1, "width": 0.6, "height": 0.1}}
  ]
}
'''),
      throwsFormatException,
    );
  });

  test('rejects an unsupported version', () {
    expect(
      () => decodeSceneDocument('''
{
  "id": "test",
  "version": 2,
  "canvas": {"fit": "cover"},
  "background": {"kind": "solid"},
  "nodes": [
    {"id": "panel", "kind": "glassPanel", "rect": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2}}
  ]
}
'''),
      throwsFormatException,
    );
  });

  test('rejects an invalid color', () {
    expect(
      () => decodeSceneDocument('''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "cover"},
  "background": {"kind": "solid", "color": "blue"},
  "nodes": [
    {"id": "panel", "kind": "glassPanel", "rect": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2}}
  ]
}
'''),
      throwsFormatException,
    );
  });

  test('rejects a scene without nodes', () {
    expect(
      () => decodeSceneDocument('''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "cover"},
  "background": {"kind": "solid"},
  "nodes": []
}
'''),
      throwsFormatException,
    );
  });
}
