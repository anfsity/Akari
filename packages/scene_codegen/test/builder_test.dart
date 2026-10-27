import 'dart:convert';
import 'dart:io';

import 'package:scene_codegen/scene_codegen.dart';
import 'package:test/test.dart';

void main() {
  test('generated Dart preserves literal strings when executed', () async {
    final properties = {
      r'$key': r'$user and ${expression}',
      'escaping': "quote' and \\ slash\nnew line\rcarriage return",
      'backslash before dollar': r'\$user',
    };
    final generated = generateScene(
      jsonEncode({
        'id': '123 test',
        'version': 2,
        'themeProperties': properties,
        'guides': [
          {'axis': 'vertical', 'position': .4},
        ],
        'styleTokens': {
          'glass': {
            'fill': '#112233',
            'gradientEnd': '#445566',
            'radius': 16,
            'textColor': '#ffffff',
            'fontSize': 24,
          },
        },
        'canvas': {'fit': 'contain'},
        'background': {
          'kind': 'custom',
          'asset': r'assets/$wallpaper.png',
          'rendererId': r'${renderer}',
          'parameters': {r'$rain': 1.5},
        },
        'nodes': [
          {
            'id': r'$node',
            'component': r'${component}',
            'styleToken': 'glass',
            'stateEffects': {'isAuthError': 'shake'},
            'motionTiming': {
              'durationMs': 800,
              'delayMs': 120,
              'curve': [.2, 0, .4, 1],
            },
            'layout': {'direction': 'column', 'gap': 12},
            'sizing': {'width': 320, 'flex': 1},
            'rect': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
            'properties': properties,
          },
          {
            'id': 'child',
            'component': 'text',
            'asset': {
              'kind': 'svg',
              'path': 'packages/test/assets/icon.svg',
              'tint': '#112233',
            },
            'parentId': r'$node',
            'rect': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
          },
          {
            'id': 'primitive',
            'component': 'scenePrimitive',
            'primitive': 'text',
            'properties': {'text': 'Portable text'},
            'rect': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
          },
        ],
      }),
    );
    final temp = await Directory.systemTemp.createTemp('scene-codegen-test-');
    addTearDown(() => temp.delete(recursive: true));
    final script = File('${temp.path}/scene.dart');
    // scene re-exports these models; use their Flutter-free source to execute
    // the generated constructors without requiring a Flutter runtime.
    await script.writeAsString('''
${generated.replaceAll('package:scene/scene.dart', 'package:scene_schema/scene_schema.dart')}
void main() {
  print(encodeSceneDocument(${getSceneDocumentVariableName('123 test')}));
}
''');
    final result = await Process.run(Platform.resolvedExecutable, [
      '--packages=${File('.dart_tool/package_config.json').absolute.path}',
      script.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final document = jsonDecode(result.stdout as String);
    expect(document['background']['asset'], r'assets/$wallpaper.png');
    expect(document['background']['rendererId'], r'${renderer}');
    expect(document['background']['parameters'], {r'$rain': 1.5});
    expect(document['nodes'][0]['id'], r'$node');
    expect(document['nodes'][0]['component'], r'${component}');
    expect(document['nodes'][0]['properties'], properties);
    expect(document['nodes'][0]['layout']['direction'], 'column');
    expect(document['nodes'][0]['sizing']['width'], 320);
    expect(document['nodes'][1]['parentId'], r'$node');
    expect(
      document['nodes'][1]['asset']['path'],
      'packages/test/assets/icon.svg',
    );
    expect(document['nodes'][1]['asset']['tint'], '#112233');
    expect(document['nodes'][2]['primitive'], 'text');
    expect(document['nodes'][2]['properties']['text'], 'Portable text');
    expect(document['themeProperties'], properties);
    expect(document['guides'], [
      {'axis': 'vertical', 'position': .4},
    ]);
    expect(document['styleTokens']['glass']['gradientEnd'], '#445566');
    expect(document['styleTokens']['glass']['radius'], 16);
    expect(document['nodes'][0]['styleToken'], 'glass');
    expect(document['nodes'][0]['stateEffects'], {'isAuthError': 'shake'});
    expect(document['nodes'][0]['motionTiming']['delayMs'], 120);
    expect(document['nodes'][0]['motionTiming']['curve'], [.2, 0, .4, 1]);
  });

  test('generates a typed document from a valid scene', () {
    final generated = generateScene('''
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
      "rect": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2},
      "action": "beginAuthentication",
      "visibleWhen": {"any": ["isAuthPrompting", "isAuthError"]}
    }
  ]
}
''');

    expect(
      generated,
      contains('SceneDocument get testSceneDocument => SceneDocument('),
    );
    expect(generated, contains('referenceWidth: 2560'));
    expect(generated, contains('referenceHeight: 1440'));
    expect(generated, contains("componentId: 'primaryAction'"));
    expect(generated, contains('interactive: true'));
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
