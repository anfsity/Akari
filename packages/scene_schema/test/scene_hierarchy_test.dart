import 'dart:convert';

import 'package:scene_schema/scene_schema.dart';
import 'package:test/test.dart';

Map<String, Object> scene(List<Map<String, Object>> nodes) => {
  'id': 'frames',
  'version': 3,
  'canvas': {'fit': 'reflow'},
  'background': {'kind': 'solid'},
  'nodes': nodes,
};

Map<String, Object> node(String id, {String? parent, bool frame = false}) => {
  'id': id,
  'component': frame ? 'frame' : 'text',
  'parentId': ?parent,
  if (frame) 'layout': {'direction': 'column', 'padding': 24, 'gap': 12},
  'rect': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
};

void main() {
  test(
    'typography paths weights and dimensions reject invalid authoring values',
    () {
      for (final style in [
        {'fontAsset': '/tmp/font.otf'},
        {'fontAsset': 'assets/../font.otf'},
        {'fontWeight': 450},
        {'fontWeight': 1000},
        {'lineHeight': 0},
        {'letterSpacing': 'wide'},
      ]) {
        final json = scene([
          {...node('a'), 'styleToken': 'type'},
        ])..['styleTokens'] = {'type': style};
        expect(
          () => decodeSceneDocument(jsonEncode(json)),
          throwsFormatException,
        );
      }
    },
  );

  test('primitive content validates once and round trips independently of theme components', () {
    for (final kind in ScenePrimitive.values) {
      final document = decodeSceneDocument(
        jsonEncode(
          scene([
            {...node('primitive'), 'primitive': kind.name},
          ]),
        ),
      );
      expect(
        decodeSceneDocument(encodeSceneDocument(document))
            .nodes
            .single
            .primitive,
        kind,
      );
    }
    for (final content in [
      {'primitive': 'unknown'},
      {
        'primitive': 'text',
        'layout': {'direction': 'row'},
      },
      {
        'primitive': 'text',
        'asset': {'path': 'assets/photo.png'},
      },
    ]) {
      expect(
        () => decodeSceneDocument(
          jsonEncode(
            scene([
              {...node('primitive'), ...content},
            ]),
          ),
        ),
        throwsFormatException,
      );
    }
  });

  test('asset defaults and overrides survive unrelated node edits and JSON round trips', () {
    final document = decodeSceneDocument(
      jsonEncode(
        scene([
          {
            ...node('image'),
            'asset': {'path': 'assets/photo.png'},
          },
          {
            ...node('icon'),
            'asset': {
              'path': 'packages/theme_test/assets/icon.svg',
              'kind': 'svg',
              'fit': 'cover',
              'tint': '#80112233',
            },
          },
        ]),
      ),
    );
    expect(document.nodes.first.asset!.kind, SceneAssetKind.image);
    expect(document.nodes.first.asset!.fit, SceneAssetFit.contain);
    final updated = document.nodes.last.copyWith(
      renderOrder: 10,
      asset: document.nodes.last.asset!.copyWith(fit: SceneAssetFit.fill),
    );
    final restored = decodeSceneDocument(
      encodeSceneDocument(
        document.copyWith(nodes: [document.nodes.first, updated]),
      ),
    ).nodes.last;
    expect(restored.asset!.path, 'packages/theme_test/assets/icon.svg');
    expect(restored.asset!.kind, SceneAssetKind.svg);
    expect(restored.asset!.fit, SceneAssetFit.fill);
    expect(restored.asset!.tint, 0x80112233);
    expect(restored.asset!.copyWith(tint: null).tint, isNull);
    expect(restored.copyWith(asset: null).asset, isNull);
  });

  test('asset nodes validate portable paths kinds fits and mutually exclusive frames', () {
    for (final asset in [
      {'path': '../icon.svg'},
      {'path': '/tmp/icon.svg'},
      {'path': r'assets/..\icon.svg'},
      {'path': 'assets/'},
      {'path': 'assets/icon.svg', 'kind': 'script'},
      {'path': 'assets/icon.svg', 'fit': 'unknown'},
      {'path': 'assets/icon.svg', 'tint': 'red'},
    ]) {
      expect(
        () => decodeSceneDocument(
          jsonEncode(
            scene([
              {...node('asset'), 'asset': asset},
            ]),
          ),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => decodeSceneDocument(
        jsonEncode(
          scene([
            {
              ...node('frame', frame: true),
              'asset': {'path': 'assets/icon.svg'},
            },
          ]),
        ),
      ),
      throwsFormatException,
    );
  });
  test('guide coordinates validate at the authoring boundary', () {
    for (final guide in [
      {'axis': 'vertical', 'position': -1},
      {'axis': 'horizontal', 'position': 2},
      {'axis': 'diagonal', 'position': .5},
    ]) {
      final json = scene([node('a')])..['guides'] = [guide];
      expect(
        () => decodeSceneDocument(jsonEncode(json)),
        throwsFormatException,
      );
    }
  });
  test(
    'background parameters round trip and reject invalid external values',
    () {
      final json = scene([node('a')]);
      json['background'] = {
        'kind': 'solid',
        'parameters': {'refraction': 1.5},
      };
      final document = decodeSceneDocument(jsonEncode(json));
      final updated = document.copyWith(
        background: document.background.copyWith(blurSigma: 8),
      );
      expect(
        decodeSceneDocument(encodeSceneDocument(updated)).background.parameters,
        {'refraction': 1.5},
      );
      for (final invalid in [
        'fast',
        {'speed': 'fast'},
        {'speed': null},
      ]) {
        json['background'] = {'kind': 'solid', 'parameters': invalid};
        expect(
          () => decodeSceneDocument(jsonEncode(json)),
          throwsFormatException,
        );
      }
    },
  );
  test('state responses accept only known triggers and effects', () {
    for (final effects in [
      {'isUnknown': 'shake'},
      {'isAuthError': 'execute'},
      {'isAuthError': 42},
    ]) {
      expect(
        () => decodeSceneDocument(
          jsonEncode(
            scene([
              {...node('a'), 'stateEffects': effects},
            ]),
          ),
        ),
        throwsFormatException,
      );
    }
  });
  test('motion timing validates before entering generated scenes', () {
    for (final invalid in [
      {'durationMs': -1},
      {'delayMs': 60001},
      {'durationMs': .5},
      {
        'curve': [0, 1, 2, 1],
      },
      {
        'curve': [0, 1],
      },
    ]) {
      expect(
        () => decodeSceneDocument(
          jsonEncode(
            scene([
              {...node('a'), 'motionTiming': invalid},
            ]),
          ),
        ),
        throwsFormatException,
      );
    }
  });
  test('validates style tokens and preserves all visual values', () {
    final json = scene([
      {...node('a'), 'styleToken': 'glass'},
    ]);
    json['styleTokens'] = {
      'glass': {
        'fill': '#112233',
        'gradientEnd': '#445566',
        'radius': 20,
        'shadowBlur': 12,
        'backgroundBlur': 8,
        'textColor': '#ffffff',
        'fontSize': 24,
      },
    };
    final original = decodeSceneDocument(jsonEncode(json));
    final restored = decodeSceneDocument(encodeSceneDocument(original));
    expect(restored.styleTokens['glass']!.gradientEnd, 0xff445566);
    expect(restored.styleTokens['glass']!.backgroundBlur, 8);
    for (final invalid in [
      {
        'glass': {'radius': -1},
      },
      {
        'glass': {'opacity': 2},
      },
      <String, Object>{},
    ]) {
      json['styleTokens'] = invalid;
      expect(
        () => decodeSceneDocument(jsonEncode(json)),
        throwsFormatException,
      );
    }
  });
  test('round trips nested layout and fixed/flexible sizing', () {
    final json = scene([
      node('frame', frame: true),
      {
        ...node('child', parent: 'frame'),
        'sizing': {'width': 320, 'height': 60, 'flex': 2},
      },
    ]);
    final document = decodeSceneDocument(jsonEncode(json));
    final restored = decodeSceneDocument(encodeSceneDocument(document));
    expect(restored.nodes.last.parentId, 'frame');
    expect(restored.nodes.first.layout!.direction, SceneLayoutDirection.column);
    expect(restored.nodes.first.layout!.gap, 12);
    expect(restored.nodes.last.sizing.width, 320);
    expect(restored.nodes.last.sizing.flex, 2);
    expect(restored.layerOrder.map((node) => node.id), ['frame', 'child']);
  });

  test('rejects missing parents, non-frame parents and cycles', () {
    for (final nodes in [
      [node('a', parent: 'missing')],
      [node('a'), node('b', parent: 'a')],
      [
        node('a', parent: 'b', frame: true),
        node('b', parent: 'a', frame: true),
      ],
    ]) {
      expect(
        () => decodeSceneDocument(jsonEncode(scene(nodes))),
        throwsFormatException,
      );
    }
  });

  test('rejects invalid spacing and sizing', () {
    for (final extra in [
      {
        'layout': {'padding': -1},
      },
      {
        'layout': {'direction': 'diagonal'},
      },
      {
        'sizing': {'width': 0},
      },
      {
        'sizing': {'flex': -1},
      },
    ]) {
      expect(
        () => decodeSceneDocument(
          jsonEncode(
            scene([
              {...node('frame'), ...extra},
            ]),
          ),
        ),
        throwsFormatException,
      );
    }
  });
}
