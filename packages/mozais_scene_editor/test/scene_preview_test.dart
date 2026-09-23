import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_greeter_ui/mozais_greeter_ui.dart';
import 'package:mozais_scene/mozais_scene.dart';
import 'package:mozais_scene_editor/src/editor_controller.dart';
import 'package:mozais_scene_editor/src/editor_settings.dart';
import 'package:mozais_scene_editor/src/editor_settings_controller.dart';
import 'package:mozais_scene_editor/src/editor_settings_scope.dart';
import 'package:mozais_scene_editor/src/editor_settings_store.dart';
import 'package:mozais_scene_editor/src/editor_strings.dart';
import 'package:mozais_scene_editor/src/english_strings.dart';
import 'package:mozais_scene_editor/src/scene_preview.dart';

const _scene = '''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "cover", "useSafeArea": false},
  "background": {"kind": "solid"},
  "nodes": [
    {
      "id": "panel",
      "kind": "glassPanel",
      "rect": {"x": 0.5, "y": 0.5, "width": 0.2, "height": 0.2}
    },
    {
      "id": "backdrop",
      "kind": "glassPanel",
      "rect": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2}
    },
    {
      "id": "hidden",
      "kind": "glassPanel",
      "rect": {"x": 0.6, "y": 0.1, "width": 0.2, "height": 0.2},
      "visibleWhen": "isDormant"
    }
  ]
}
''';

void main() {
  late Directory directory;
  late SceneEditorController controller;
  late EditorSettingsController settings;
  late GreeterFeature feature;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('mozais_preview');
    final file = File('${directory.path}/test.scene.json')
      ..writeAsStringSync(_scene);
    controller = SceneEditorController()..setPath(file.path);
    await controller.open();
    settings = EditorSettingsController(
      EditorSettingsStore(File('${directory.path}/settings.json')),
      initial: EditorSettings.defaults,
    );
    feature = GreeterFeature(gateway: DemoGreeterGateway());
  });

  tearDown(() {
    feature.dispose();
    settings.dispose();
    directory.deleteSync(recursive: true);
  });

  Future<void> pumpPreview(
    WidgetTester tester, {
    PreviewMode mode = PreviewMode.outline,
  }) async {
    await tester.pumpWidget(
      EditorStringsScope(
        strings: const EnglishStrings(),
        child: EditorSettingsScope(
          controller: settings,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 450,
                child: ScenePreview(
                  controller: controller,
                  feature: feature,
                  mode: mode,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect previewRect(WidgetTester tester) {
    final origin = tester.getTopLeft(find.byType(SceneRuntime));
    final size = tester.getSize(find.byType(SceneRuntime));
    return origin & size;
  }

  Future<void> pumpInteractivePreview(WidgetTester tester) async {
    await tester.pumpWidget(
      EditorStringsScope(
        strings: const EnglishStrings(),
        child: EditorSettingsScope(
          controller: settings,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 450,
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => ScenePreview(
                    controller: controller,
                    feature: feature,
                    mode: PreviewMode.outline,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('dragging inside the node moves it', (tester) async {
    await pumpPreview(tester);
    final preview = previewRect(tester);

    final center = preview.topLeft +
        Offset(preview.width * 0.6, preview.height * 0.6);
    await tester.dragFrom(center, const Offset(40, 20));
    await tester.pump();

    final rect = controller.selectedNode!.rect;
    expect(rect.x, greaterThan(0.5));
    expect(rect.y, greaterThan(0.5));
  });

  testWidgets('dragging the corner handle resizes the node', (tester) async {
    await pumpPreview(tester);
    final preview = previewRect(tester);

    final handle = preview.topLeft +
        Offset(preview.width * 0.7 + 4, preview.height * 0.7 + 4);
    await tester.dragFrom(handle, const Offset(40, 20));
    await tester.pump();

    final rect = controller.selectedNode!.rect;
    expect(rect.width, greaterThan(0.2));
    expect(rect.height, greaterThan(0.2));
  });

  testWidgets('dragging the dot rotates in plane', (tester) async {
    await pumpPreview(tester);
    final preview = previewRect(tester);

    final dot = preview.topLeft +
        Offset(preview.width * 0.6, preview.height * 0.5 - 30);
    await tester.dragFrom(dot, const Offset(30, 0));
    await tester.pump();

    expect(controller.selectedNode!.transform.rotationZ, greaterThan(0));
  });

  testWidgets('dragging the trackball rotates in 3D', (tester) async {
    await pumpPreview(tester);
    final preview = previewRect(tester);

    final trackball = preview.topLeft +
        Offset(preview.width * 0.6, preview.height * 0.7 + 44);
    await tester.dragFrom(trackball, const Offset(40, 20));
    await tester.pump();

    final transform = controller.selectedNode!.transform;
    expect(transform.rotationY, greaterThan(0));
    expect(transform.rotationX, lessThan(0));
  });

  testWidgets('clicking another node selects it', (tester) async {
    await pumpPreview(tester);
    final preview = previewRect(tester);

    await tester.tapAt(
      preview.topLeft + Offset(preview.width * 0.2, preview.height * 0.2),
    );
    await tester.pump();

    expect(controller.selectedNodeId, 'backdrop');
  });

  testWidgets('hides the selection overlay for an invisible node', (
    tester,
  ) async {
    await pumpInteractivePreview(tester);

    controller.select('hidden');
    await tester.pump();
    expect(find.byKey(const ValueKey('selectionOverlay')), findsNothing);

    controller.select('panel');
    await tester.pump();
    expect(find.byKey(const ValueKey('selectionOverlay')), findsOneWidget);
  });

  testWidgets('clicking picks a visible node while a hidden one is selected', (
    tester,
  ) async {
    await pumpInteractivePreview(tester);
    final preview = previewRect(tester);

    controller.select('hidden');
    await tester.pump();
    await tester.tapAt(
      preview.topLeft + Offset(preview.width * 0.2, preview.height * 0.2),
    );
    await tester.pump();

    expect(controller.selectedNodeId, 'backdrop');
  });

  testWidgets('real mode embeds the greeter adapter', (tester) async {
    await pumpPreview(tester, mode: PreviewMode.real);

    expect(find.byType(GreeterSceneAdapter), findsOneWidget);
  });

  testWidgets('keeps the embedded scene when only the selection changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      EditorStringsScope(
        strings: const EnglishStrings(),
        child: EditorSettingsScope(
          controller: settings,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 450,
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => ScenePreview(
                    controller: controller,
                    feature: feature,
                    mode: PreviewMode.outline,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final before = tester.widget<SceneRuntime>(find.byType(SceneRuntime));
    controller.select('panel');
    await tester.pump();
    final after = tester.widget<SceneRuntime>(find.byType(SceneRuntime));

    expect(identical(before, after), isTrue);
  });
}
