import 'dart:convert';
import 'dart:io';

import 'editor_settings.dart';

/// Reads and writes editor settings under the user's config directory.
///
/// The file is an external boundary, so load errors fall back to defaults
/// instead of surfacing in the UI.
class EditorSettingsStore {
  EditorSettingsStore([this._file]);

  final File? _file;

  File get file => _file ?? _defaultFile();

  EditorSettings load() {
    final file = this.file;
    if (!file.existsSync()) {
      return EditorSettings.defaults;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) {
        return EditorSettings.defaults;
      }
      return EditorSettings.fromJson(decoded);
    } on Object {
      return EditorSettings.defaults;
    }
  }

  Future<void> save(EditorSettings settings) async {
    final file = this.file;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()));
  }
}

File _defaultFile() {
  final environment = Platform.environment;
  final xdgConfig = environment['XDG_CONFIG_HOME'];
  final configHome = xdgConfig != null && xdgConfig.isNotEmpty
      ? xdgConfig
      : '${environment['HOME']}/.config';
  return File('$configHome/mozais/scene_editor.json');
}
