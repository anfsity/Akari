import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene_editor/src/editor_controller.dart';
import 'package:mozais_scene_editor/src/editor_strings.dart';
import 'package:mozais_scene_editor/src/english_strings.dart';
import 'package:mozais_scene_editor/src/inspector_panel.dart';

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
  late SceneEditorController controller;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('mozais_inspector');
    final file = File('${directory.path}/test.scene.json')
      ..writeAsStringSync(_scene);
    controller = SceneEditorController()..setPath(file.path);
    await controller.open();
  });

  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      EditorStringsScope(
        strings: const EnglishStrings(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 600,
              child: InspectorPanel(controller: controller),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('opens on the document tab', (tester) async {
    await pump(tester);

    expect(find.text('Document'), findsOneWidget);
    expect(find.text('Canvas'), findsOneWidget);
  });

  testWidgets('switches to the node identity tab', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Identity'));
    await tester.pumpAndSettle();

    expect(find.text('kind'), findsOneWidget);
  });
}
