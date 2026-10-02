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
