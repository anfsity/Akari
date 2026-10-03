import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

import 'package:shadcn_flutter/shadcn_flutter.dart' show ThemeMode;
import 'package:theme_studio/src/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theme_studio/src/studio_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preferences persist independently of scene history', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await StudioPreferences.load()).themeMode, ThemeMode.system);
    await const StudioPreferences(
      themeMode: ThemeMode.light,
      palette: StudioPalette.violet,
      showGrid: true,
      snapToGrid: true,
      gridSize: 32,
    ).save();
    final restored = await StudioPreferences.load();
    expect(restored.themeMode, ThemeMode.light);
    expect(restored.palette, StudioPalette.violet);
    expect(restored.showGrid, isTrue);
    expect(restored.snapToGrid, isTrue);
    expect(restored.gridSize, 32);
  });

  test('legacy appearance choices migrate with the default palette', () async {
    for (final dark in [true, false]) {
      SharedPreferences.setMockInitialValues({
        'mozais.studio.preferences': jsonEncode({
          'darkMode': dark,
          'showGrid': true,
          'snapToGrid': false,
          'gridSize': 48,
        }),
      });
      final restored = await StudioPreferences.load();
      expect(restored.themeMode, dark ? ThemeMode.dark : ThemeMode.light);
      expect(restored.palette, StudioPalette.zinc);
      expect(restored.gridSize, 48);
      await restored.save();
      expect((await StudioPreferences.load()).themeMode, restored.themeMode);
    }
  });

  test(
    'unknown theme modes and palettes are rejected at storage boundary',
    () async {
      for (final entry in [
        {'themeMode': 'unknown'},
        {'palette': 'unknown'},
      ]) {
        SharedPreferences.setMockInitialValues({
          'mozais.studio.preferences': jsonEncode({
            'themeMode': 'system',
            'palette': 'zinc',
            'showGrid': false,
            'snapToGrid': false,
            'gridSize': 24,
            ...entry,
          }),
        });
        await expectLater(StudioPreferences.load(), throwsFormatException);
      }
    },
  );

  test('corrupt stored preferences can be replaced with defaults', () async {
    SharedPreferences.setMockInitialValues({
      'mozais.studio.preferences': '{"gridSize":0}',
    });
    await expectLater(StudioPreferences.load(), throwsFormatException);
    await const StudioPreferences().save();
    expect((await StudioPreferences.load()).gridSize, 24);
  });
}
