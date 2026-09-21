import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene_editor/src/editor_controller.dart';
import 'package:mozais_scene_editor/src/editor_strings.dart';
import 'package:mozais_scene_editor/src/english_strings.dart';
import 'package:mozais_scene_editor/src/node_list_panel.dart';
import 'package:mozais_scene_editor/src/pane_divider.dart';

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
    directory = Directory.systemTemp.createTempSync('mozais_node_list');
    final file = File('${directory.path}/test.scene.json')
      ..writeAsStringSync(_scene);
    controller = SceneEditorController()..setPath(file.path);
    await controller.open();
  });

  tearDown(() => directory.deleteSync(recursive: true));

  testWidgets('dragging the divider resizes the predicates pane', (
    tester,
  ) async {
    await tester.pumpWidget(
      EditorStringsScope(
        strings: const EnglishStrings(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              height: 600,
              child: NodeListPanel(controller: controller),
            ),
          ),
        ),
      ),
    );

    final pane = find.byKey(const ValueKey('activePredicatesPane'));
    final before = tester.getSize(pane).height;

    await tester.drag(find.byType(PaneDivider), const Offset(0, 40));
    await tester.pump();

    expect(tester.getSize(pane).height, lessThan(before));
  });
}
