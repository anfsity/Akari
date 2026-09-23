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

  test('updates the document canvas and marks it dirty', () async {
    final controller = SceneEditorController()..setPath(file.path);
    await controller.open();

    controller.updateDocument(
      (document) => document.copyWith(
        canvas: document.canvas.copyWith(fit: SceneCanvasFit.contain),
      ),
    );

    expect(controller.document!.canvas.fit, SceneCanvasFit.contain);
    expect(controller.dirty, isTrue);
  });

  test('imports an image background into the assets directory', () async {
    final assets = Directory('${directory.path}/assets');
    final source = File('${directory.path}/wallpaper.png')
      ..writeAsBytesSync([1, 2, 3]);
    final controller = SceneEditorController(assets)
      ..setPath(file.path);
    await controller.open();

    expect(await controller.importBackgroundAsset(source), isTrue);

    expect(controller.document!.background.kind, SceneBackgroundKind.image);
    expect(controller.document!.background.asset, 'assets/wallpaper.png');
    expect(File('${assets.path}/wallpaper.png').readAsBytesSync(), [1, 2, 3]);
    expect(controller.dirty, isTrue);
    expect(
      controller.status.kind,
      EditorStatusKind.backgroundImported,
    );
  });

  test('imports a video background as the video kind', () async {
    final assets = Directory('${directory.path}/assets');
    final source = File('${directory.path}/clip.mp4')..writeAsBytesSync([1]);
    final controller = SceneEditorController(assets)
      ..setPath(file.path);
    await controller.open();

    await controller.importBackgroundAsset(source);

    expect(controller.document!.background.kind, SceneBackgroundKind.video);
    expect(controller.document!.background.asset, 'assets/clip.mp4');
  });

  test('does not overwrite an existing asset on import', () async {
    final assets = Directory('${directory.path}/assets')..createSync();
    File('${assets.path}/wallpaper.png').writeAsBytesSync([9]);
    final source = File('${directory.path}/wallpaper.png')
      ..writeAsBytesSync([1]);
    final controller = SceneEditorController(assets)
      ..setPath(file.path);
    await controller.open();

    await controller.importBackgroundAsset(source);

    expect(controller.document!.background.asset, 'assets/wallpaper-2.png');
    expect(File('${assets.path}/wallpaper.png').readAsBytesSync(), [9]);
    expect(File('${assets.path}/wallpaper-2.png').readAsBytesSync(), [1]);
  });
}
