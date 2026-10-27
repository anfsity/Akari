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
  if (parent != null) 'parentId': parent,
  if (frame) 'layout': {'direction': 'column', 'padding': 24, 'gap': 12},
  'rect': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
};

void main() {
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
