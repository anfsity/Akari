import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene_editor/src/editor_controller.dart';
import 'package:mozais_scene_editor/src/editor_status.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

const _scene = '''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "cover"},
  "background": {"kind": "solid"},
  "nodes": [
    {
      "id": "panel",
      "kind": "glassPanel",
      "rect": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2}
    }
  ]
}
''';

void main() {
  late Directory directory;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('mozais_editor_test');
    file = File('${directory.path}/test.scene.json')..writeAsStringSync(_scene);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('opens a scene and selects its first node', () async {
    final controller = SceneEditorController()
      ..setPath(file.path);

    await controller.open();

    expect(controller.document, isNotNull);
    expect(controller.selectedNodeId, 'panel');
    expect(controller.dirty, isFalse);
  });

  test('saves an edit back to disk', () async {
    final controller = SceneEditorController()..setPath(file.path);
    await controller.open();

    controller.updateSelected((node) => node.copyWith(z: 5));
    expect(controller.dirty, isTrue);

    await controller.save();
    expect(controller.dirty, isFalse);

    final saved = decodeSceneDocument(file.readAsStringSync());
    expect(saved.nodes.single.z, 5);
  });

  test('adds and deletes nodes without emptying the document', () async {
    final controller = SceneEditorController()..setPath(file.path);
    await controller.open();

    controller.addNode();
    expect(controller.document!.nodes, hasLength(2));
    expect(controller.selectedNodeId, 'node1');

    controller.deleteSelected();
    expect(controller.document!.nodes, hasLength(1));

    controller.deleteSelected();
    expect(controller.document!.nodes, hasLength(1));
    expect(controller.status.kind, EditorStatusKind.keepOneNode);
  });

  test('reports an open failure without dropping the document', () async {
    final controller = SceneEditorController()
      ..setPath('${directory.path}/missing.scene.json');

    await controller.open();

    expect(controller.document, isNull);
    expect(controller.status.kind, EditorStatusKind.openFailed);
  });
}
