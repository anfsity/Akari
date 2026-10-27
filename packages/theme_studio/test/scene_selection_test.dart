import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/node_geometry.dart';
import 'package:theme_studio/src/scene_editor.dart';

void main() {
  late Directory directory;
  late SceneEditor editor;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('scene-selection-');
    final file = File('${directory.path}/scene.json')
      ..writeAsStringSync(
        encodeSceneDocument(
          const SceneDocument(
            id: 'test',
            version: currentSceneVersion,
            canvas: SceneCanvas(),
            background: SceneBackground(kind: SceneBackgroundKind.solid),
            nodes: [
              SceneNode(
                id: 'a',
                componentId: 'text',
                rect: SceneRect(x: .1, y: .1, width: .2, height: .1),
              ),
              SceneNode(
                id: 'b',
                componentId: 'text',
                rect: SceneRect(x: .5, y: .4, width: .2, height: .1),
              ),
              SceneNode(
                id: 'c',
                componentId: 'text',
                rect: SceneRect(x: .8, y: .7, width: .1, height: .1),
              ),
            ],
          ),
        ),
      );
    editor = SceneEditor(file);
  });
  tearDown(() {
    editor.dispose();
    directory.deleteSync(recursive: true);
  });

  Map<String, SceneNodeGeometry> geometry() => calculateSceneLayout(
    document: editor.document,
    size: const Size(1920, 1080),
  );

  test('selection is transient; group and ungroup preserve rendered geometry and history', () {
    editor.selectNode('b', toggle: true);
    expect(editor.selectedIds, {'a', 'b'});
    expect(editor.isDirty, isFalse);
    expect(editor.canUndo, isFalse);
    final before = geometry();
    editor.groupSelection();
    final frameId = editor.selectedId;
    expect(editor.selectedNode.layout, isNotNull);
    for (final id in ['a', 'b']) {
      final actual = geometry()[id]!.bounds;
      final expected = before[id]!.bounds;
      expect((actual.topLeft - expected.topLeft).distance, lessThan(1e-8));
      expect(
        (actual.bottomRight - expected.bottomRight).distance,
        lessThan(1e-8),
      );
    }
    editor.undo();
    expect(editor.selectedIds, {'a', 'b'});
    expect(editor.document.nodes.length, 3);
    editor.redo();
    expect(editor.selectedId, frameId);
    editor.ungroupSelection();
    expect(editor.selectedIds, {'a', 'b'});
    expect(
      editor.document.nodes.every((node) => node.parentId == null),
      isTrue,
    );
    editor.save();
    expect(editor.isDirty, isFalse);
  });

  test('batch alignment and distribution each make one undo step', () {
    editor.selectNodes({'a', 'b', 'c'});
    editor.alignSelection(NodeAlignment.left);
    expect(editor.selectedNodes.map((node) => node.rect.x).toSet().length, 1);
    editor.undo();
    expect(editor.canUndo, isFalse);
    editor.distributeSelection(horizontal: false);
    final nodes = editor.selectedNodes;
    final firstGap = nodes[1].rect.y - nodes[0].rect.y - nodes[0].rect.height;
    final secondGap = nodes[2].rect.y - nodes[1].rect.y - nodes[1].rect.height;
    expect(firstGap, closeTo(secondGap, 1e-9));
    editor.undo();
    expect(editor.canUndo, isFalse);
  });

  test(
    'copy remaps an entire subtree; delete and undo restore it atomically',
    () {
      editor.selectNodes({'a', 'b'});
      editor.groupSelection();
      final frame = editor.selectedId;
      editor.duplicateSelectedNode();
      final copy = editor.selectedId;
      expect(copy, isNot(frame));
      expect(editor.document.getChildren(copy).length, 2);
      expect(
        editor.document
            .getChildren(copy)
            .every((node) => node.id.endsWith('-copy')),
        isTrue,
      );
      editor.deleteSelectedNode();
      expect(
        editor.document.nodes.any((node) => node.parentId == copy),
        isFalse,
      );
      editor.undo();
      expect(editor.selectedId, copy);
      expect(editor.document.getChildren(copy).length, 2);
    },
  );

  test(
    'invalid drafts block batch commands; required descendants stay protected',
    () {
      editor.selectNodes({'a', 'b'});
      editor.inspector.getField('Width').text = '-1';
      editor.groupSelection();
      expect(editor.document.nodes.length, 3);
      editor.inspector.resetNode(editor.selectedNode);
      editor.groupSelection();
      editor.updateAuthoring(
        componentCatalog: const ThemeComponentCatalog(),
        layout: const ThemeLayoutDefinition(
          sceneId: 'test',
          label: 'Required',
          slots: [
            ThemeLayoutSlot(
              label: 'Account',
              isRequired: true,
              defaultNode: SceneNode(
                id: 'a',
                componentId: 'text',
                rect: SceneRect(x: 0, y: 0, width: 1, height: 1),
              ),
            ),
          ],
        ),
      );
      expect(editor.canDeleteNode, isFalse);
      expect(editor.canDuplicateNode, isFalse);
      expect(editor.deleteSelectedNode, throwsStateError);
    },
  );
}
