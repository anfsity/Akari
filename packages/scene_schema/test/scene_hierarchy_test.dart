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
