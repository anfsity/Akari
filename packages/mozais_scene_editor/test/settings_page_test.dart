import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene_editor/src/editor_settings.dart';
import 'package:mozais_scene_editor/src/editor_settings_controller.dart';
import 'package:mozais_scene_editor/src/editor_settings_store.dart';
import 'package:mozais_scene_editor/src/editor_strings.dart';
import 'package:mozais_scene_editor/src/english_strings.dart';
import 'package:mozais_scene_editor/src/editor_theme.dart';
import 'package:mozais_scene_editor/src/settings_page.dart';

void main() {
  late Directory directory;
  late EditorSettingsController controller;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('mozais_settings_page');
    controller = EditorSettingsController(
      EditorSettingsStore(File('${directory.path}/scene_editor.json')),
      initial: EditorSettings.defaults,
    );
  });

  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> pumpPage(WidgetTester tester) {
    return tester.pumpWidget(
      EditorStringsScope(
        strings: const EnglishStrings(),
        child: MaterialApp(
          home: SettingsPage(controller: controller),
        ),
      ),
    );
  }

  testWidgets('renders the grouped options', (tester) async {
    await pumpPage(tester);

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Editing'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
  });

  testWidgets('reset restores the default theme', (tester) async {
    controller.update(
      controller.settings.copyWith(themeId: EditorThemeId.dracula),
    );
    await pumpPage(tester);

    await tester.tap(find.text('Reset to defaults'));
    await tester.pump();

    expect(controller.settings, EditorSettings.defaults);
  });
}
