import 'dart:async';

import 'package:flutter/foundation.dart';

import 'editor_locale.dart';
import 'editor_settings.dart';
import 'editor_settings_store.dart';
import 'editor_strings.dart';

/// Owns the persisted [EditorSettings] and rebuilds the editor on change.
class EditorSettingsController extends ChangeNotifier {
  EditorSettingsController(this._store, {required EditorSettings initial})
      : _settings = initial;

  factory EditorSettingsController.load({EditorSettingsStore? store}) {
    final resolved = store ?? EditorSettingsStore();
    return EditorSettingsController(resolved, initial: resolved.load());
  }

  final EditorSettingsStore _store;
  EditorSettings _settings;

  EditorSettings get settings => _settings;

  EditorStrings get strings => editorStringsFor(_settings.locale);

  void update(EditorSettings settings) {
    if (settings == _settings) {
      return;
    }
    _settings = settings;
    notifyListeners();
    unawaited(_store.save(settings));
  }

  void resetToDefaults() => update(EditorSettings.defaults);
}
