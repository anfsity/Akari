import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene_editor/src/document_panel.dart';
import 'package:mozais_scene_editor/src/editor_controller.dart';
import 'package:mozais_scene_editor/src/editor_strings.dart';
import 'package:mozais_scene_editor/src/english_strings.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

const _scene = '''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "cover"},
  "background": {"kind": "solid", "color": "#0d151a"},
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
    directory = Directory.systemTemp.createTempSync('mozais_document_panel');
    final file = File('${directory.path}/test.scene.json')
      ..writeAsStringSync(_scene);
    controller = SceneEditorController(
      Directory('${directory.path}/assets'),
    )..setPath(file.path);
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
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => DocumentPanel(controller: controller),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('changes the canvas fit', (tester) async {
    await pump(tester);

    await tester.tap(find.byType(DropdownButton<SceneCanvasFit>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('contain').last);
    await tester.pumpAndSettle();

    expect(controller.document!.canvas.fit, SceneCanvasFit.contain);
  });

  testWidgets('toggles the safe area', (tester) async {
    await pump(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.document!.canvas.useSafeArea, isFalse);
  });

  testWidgets('changes the background kind and warns about video', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byType(DropdownButton<SceneBackgroundKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('video').last);
    await tester.pumpAndSettle();

    expect(controller.document!.background.kind, SceneBackgroundKind.video);
    expect(
      find.text('No video renderer yet; this background renders solid.'),
      findsOneWidget,
    );
  });

  testWidgets('edits the background color as hex', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextFormField), '#112233');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(controller.document!.background.color, 0xff112233);
  });
}
