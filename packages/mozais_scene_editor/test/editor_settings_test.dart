import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene_editor/src/editor_locale.dart';
import 'package:mozais_scene_editor/src/editor_settings.dart';
import 'package:mozais_scene_editor/src/editor_settings_store.dart';
import 'package:mozais_scene_editor/src/editor_theme.dart';

void main() {
  late Directory directory;
  late File file;
  late EditorSettingsStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('mozais_settings_test');
    file = File('${directory.path}/scene_editor.json');
    store = EditorSettingsStore(file);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('returns defaults when no settings file exists', () {
    expect(store.load(), EditorSettings.defaults);
  });

  test('round-trips settings through disk', () async {
    const settings = EditorSettings(
      themeId: EditorThemeId.dracula,
      locale: 'en',
      confirmUnsavedChanges: false,
      gridSnap: true,
      previewAspectRatio: 4 / 3,
      defaultScenePath: '/tmp/scene.json',
    );

    await store.save(settings);

    expect(store.load(), settings);
  });

  test('falls back to defaults for malformed settings', () {
    file.writeAsStringSync('not json');

    expect(store.load(), EditorSettings.defaults);
  });

  test('ignores unknown enum and aspect-ratio values', () {
    file.writeAsStringSync('''
{
  "themeId": "solarized",
  "previewAspectRatio": 2.5
}
''');

    final settings = store.load();

    expect(settings.themeId, EditorSettings.defaults.themeId);
    expect(settings.previewAspectRatio, EditorSettings.defaults.previewAspectRatio);
  });

  test('resolves the requested locale and falls back for unknown codes', () {
    expect(editorStringsFor('en').appTitle, 'Mozais Scene Editor');
    expect(editorStringsFor('xx').appTitle, 'Mozais Scene Editor');
  });

  test('looks up every named editor theme', () {
    for (final id in EditorThemeId.values) {
      expect(editorThemeFor(id).id, id);
    }
  });
}
