import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:theme_studio/src/scene_editor.dart';

void main() {
  late Directory directory;
  late File file;
  late SceneEditor editor;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('scene-editor-');
    file = File('${directory.path}/test.scene.json')
      ..writeAsStringSync(
        encodeSceneDocument(
          const SceneDocument(
            id: 'test',
            version: currentSceneVersion,
            canvas: SceneCanvas(),
            background: SceneBackground(kind: SceneBackgroundKind.solid),
            nodes: [
              SceneNode(
                id: 'panel',
                componentId: 'panel',
                rect: SceneRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
                transform: SceneTransform(pivotX: 0.2),
                properties: {'variant': 'compact'},
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

  test('edit, undo, redo and save preserve the complete scene', () {
    editor.updateNode(editor.selectedNode.copyWith(z: 3));
    expect(editor.isDirty, isTrue);
    editor.undo();
    expect(editor.isDirty, isFalse);
    expect(editor.selectedNode.z, 0);
    editor.redo();
    editor.save();
    final restored = decodeSceneDocument(file.readAsStringSync());
    expect(restored.nodes.single.z, 3);
    expect(restored.nodes.single.transform.pivotX, 0.2);
    expect(restored.nodes.single.properties, {'variant': 'compact'});
    expect(editor.isDirty, isFalse);
    editor.undo();
    expect(editor.isDirty, isTrue);
    editor.redo();
    expect(editor.isDirty, isFalse);
    expect(directory.listSync(), hasLength(1));
  });

  test('draft commands work without a mounted inspector', () {
    editor.inspector.getField('X').text = '0.2';
    editor.undo();
    expect(editor.selectedNode.rect.x, 0.1);
    expect(editor.inspector.hasDraft, isFalse);
    editor.redo();
    expect(editor.selectedNode.rect.x, 0.2);

    editor.inspector.getField('X').text = '0.3';
    editor.duplicateSelectedNode();
    expect(editor.document.nodes.map((node) => node.rect.x), [0.3, 0.3]);
    editor.inspector.getField('X').text = '0.4';
    editor.selectNode('panel');
    expect(editor.document.nodes.last.rect.x, 0.4);
    expect(editor.inspector.getField('X').text, '0.3');

    editor.inspector.getField('X').text = '0.2';
    expect(editor.save(), isTrue);
    expect(
      decodeSceneDocument(file.readAsStringSync()).nodes.first.rect.x,
      0.2,
    );
  });

  test('invalid drafts block document commands and reload clears them', () {
    editor.duplicateSelectedNode();
    final document = editor.document;
    final source = file.readAsStringSync();
    editor.inspector.getField('Width').text = '2';
    editor.undo();
    editor.redo();
    editor.duplicateSelectedNode();
    editor.deleteSelectedNode();
    editor.updateScene(canvas: const SceneCanvas(referenceWidth: 1600));
    expect(editor.selectNode('panel'), isFalse);
    expect(editor.save(), isFalse);
    expect(editor.document, same(document));
    expect(editor.selectedId, 'panel-copy');
    expect(file.readAsStringSync(), source);
    expect(editor.inspector.error, contains('non-normalized rect'));

    editor.reload();
    expect(editor.inspector.hasDraft, isFalse);
    expect(editor.inspector.error, isNull);
    expect(editor.inspector.getField('Width').text, '0.5');
  });

  test('equivalent drafts clear without creating history', () {
    editor.inspector.getField('X').text = '0.10';
    expect(editor.applyDraft(), isTrue);
    expect(editor.inspector.hasDraft, isFalse);
    expect(editor.canUndo, isFalse);
    expect(editor.isDirty, isFalse);
  });

  test('invalid geometry leaves the working scene and history intact', () {
    expect(
      () => editor.updateNode(
        editor.selectedNode.copyWith(
          rect: editor.selectedNode.rect.copyWith(width: 1),
        ),
      ),
      throwsFormatException,
    );
    expect(editor.selectedNode.rect.width, 0.5);
    expect(editor.canUndo, isFalse);
    expect(editor.isDirty, isFalse);
  });

  test(
    'duplicate preserves node configuration and restores selection in history',
    () {
      editor.updateNode(
        editor.selectedNode.copyWith(
          z: 4,
          renderOrder: 2,
          focusOrder: 3,
          motion: SceneMotionPreset.fade,
          interactive: true,
          visibleWhen: const ScenePredicateCondition(ScenePredicate.isDormant),
        ),
      );
      final original = editor.selectedNode;
      editor.duplicateSelectedNode();
      expect(editor.selectedId, 'panel-copy');
      expect(editor.document.nodes.map((node) => node.id), [
        'panel',
        'panel-copy',
      ]);
      expect(
        encodeSceneDocument(
          editor.document.copyWith(
            nodes: [editor.selectedNode.copyWith(id: original.id)],
          ),
        ),
        encodeSceneDocument(editor.document.copyWith(nodes: [original])),
      );
      editor.undo();
      expect(editor.document.nodes, hasLength(1));
      expect(editor.selectedId, 'panel');
      editor.redo();
      expect(editor.selectedId, 'panel-copy');
      editor.save();
      expect(decodeSceneDocument(file.readAsStringSync()).nodes, hasLength(2));
      expect(editor.isDirty, isFalse);
    },
  );

  test('duplicate allocates unique ids and new edits clear redo', () {
    editor.duplicateSelectedNode();
    editor.selectNode('panel');
    editor.duplicateSelectedNode();
    expect(editor.selectedId, 'panel-copy-2');
    editor.selectNode('panel');
    editor.duplicateSelectedNode();
    expect(editor.selectedId, 'panel-copy-3');
    editor.undo();
    expect(editor.selectedId, 'panel');
    editor.duplicateSelectedNode();
    expect(editor.selectedId, 'panel-copy-3');
    expect(editor.canRedo, isFalse);
  });

  test('delete selects a neighbor and undo restores the deleted node', () {
    editor.duplicateSelectedNode();
    editor.selectNode('panel');
    editor.duplicateSelectedNode();
    editor.deleteSelectedNode();
    expect(editor.selectedId, 'panel-copy');
    expect(editor.document.nodes.map((node) => node.id), [
      'panel',
      'panel-copy',
    ]);
    editor.undo();
    expect(editor.selectedId, 'panel-copy-2');
    expect(editor.document.nodes, hasLength(3));
    editor.redo();
    expect(editor.selectedId, 'panel-copy');
    editor.deleteSelectedNode();
    expect(editor.selectedId, 'panel');
    expect(editor.canDeleteNode, isFalse);
    expect(editor.isDirty, isFalse);
    editor.undo();
    expect(editor.selectedId, 'panel-copy');
    editor.selectNode('panel');
    editor.deleteSelectedNode();
    expect(editor.selectedId, 'panel-copy');
    editor.save();
    expect(
      decodeSceneDocument(file.readAsStringSync()).nodes.single.id,
      'panel-copy',
    );
  });

  test('the last node cannot be deleted and rejection adds no history', () {
    expect(editor.canDeleteNode, isFalse);
    expect(editor.deleteSelectedNode, throwsStateError);
    expect(editor.selectedNode.id, 'panel');
    expect(editor.canUndo, isFalse);
    expect(editor.isDirty, isFalse);
  });

  test('saving detects external edits and keeps unsaved work', () {
    editor.updateNode(editor.selectedNode.copyWith(z: 3));
    file.writeAsStringSync('external edit');
    expect(editor.save, throwsA(isA<FileSystemException>()));
    expect(file.readAsStringSync(), 'external edit');
    expect(editor.selectedNode.z, 3);
    expect(editor.isDirty, isTrue);
    expect(editor.reload, throwsFormatException);
    expect(editor.selectedNode.z, 3);
  });

  test('a new edit after undo clears redo, and no-op edits add no history', () {
    editor.updateNode(editor.selectedNode);
    expect(editor.canUndo, isFalse);
    editor.updateNode(editor.selectedNode.copyWith(z: 1));
    editor.undo();
    editor.updateNode(editor.selectedNode.copyWith(z: 2));
    expect(editor.canRedo, isFalse);
    editor.reload();
    expect(editor.selectedNode.z, 0);
    expect(editor.canUndo, isFalse);
    expect(editor.isDirty, isFalse);
  });
}
