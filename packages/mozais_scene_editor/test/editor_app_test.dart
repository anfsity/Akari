import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene_editor/src/editor_app.dart';
import 'package:mozais_scene_editor/src/editor_settings.dart';
import 'package:mozais_scene_editor/src/editor_settings_controller.dart';
import 'package:mozais_scene_editor/src/editor_settings_scope.dart';
import 'package:mozais_scene_editor/src/editor_settings_store.dart';
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
  late EditorSettingsController settings;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('mozais_editor_app');
    File('${directory.path}/test.scene.json').writeAsStringSync(_scene);
    settings = EditorSettingsController(
      EditorSettingsStore(File('${directory.path}/settings.json')),
      initial: EditorSettings(
        defaultScenePath: '${directory.path}/test.scene.json',
      ),
    );
  });

  tearDown(() {
    settings.dispose();
    directory.deleteSync(recursive: true);
  });

  testWidgets('collapses and expands the inspector', (tester) async {
    await tester.pumpWidget(
      EditorSettingsScope(
        controller: settings,
        child: EditorStringsScope(
          strings: const EnglishStrings(),
          child: MaterialApp(home: EditorScreen(settings: settings)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InspectorPanel), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse inspector'));
    await tester.pumpAndSettle();
    expect(find.byType(InspectorPanel), findsNothing);

    await tester.tap(find.byTooltip('Expand inspector'));
    await tester.pumpAndSettle();
    expect(find.byType(InspectorPanel), findsOneWidget);
  });
}
