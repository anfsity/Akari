import 'editor_locale.dart';
import 'editor_theme.dart';

/// The aspect ratios offered in settings. The value is width / height.
const editorAspectRatios = <String, double>{
  '16:9': 16 / 9,
  '16:10': 16 / 10,
  '4:3': 4 / 3,
  '21:9': 21 / 9,
};

/// Persisted editor preferences. These never affect the greeter's document or
/// theme; they only configure the authoring tool.
class EditorSettings {
  const EditorSettings({
    this.themeId = EditorThemeId.aurora,
    this.locale = defaultEditorLocaleCode,
    this.confirmUnsavedChanges = true,
    this.gridSnap = false,
    this.previewAspectRatio = 16 / 9,
    this.defaultScenePath = '',
  });

  static const defaults = EditorSettings();

  final EditorThemeId themeId;
  final String locale;
  final bool confirmUnsavedChanges;
  final bool gridSnap;
  final double previewAspectRatio;
  final String defaultScenePath;

  EditorSettings copyWith({
    EditorThemeId? themeId,
    String? locale,
    bool? confirmUnsavedChanges,
    bool? gridSnap,
    double? previewAspectRatio,
    String? defaultScenePath,
  }) {
    return EditorSettings(
      themeId: themeId ?? this.themeId,
      locale: locale ?? this.locale,
      confirmUnsavedChanges:
          confirmUnsavedChanges ?? this.confirmUnsavedChanges,
      gridSnap: gridSnap ?? this.gridSnap,
      previewAspectRatio: previewAspectRatio ?? this.previewAspectRatio,
      defaultScenePath: defaultScenePath ?? this.defaultScenePath,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'themeId': themeId.name,
      'locale': locale,
      'confirmUnsavedChanges': confirmUnsavedChanges,
      'gridSnap': gridSnap,
      'previewAspectRatio': previewAspectRatio,
      'defaultScenePath': defaultScenePath,
    };
  }

  factory EditorSettings.fromJson(Map<String, Object?> json) {
    return EditorSettings(
      themeId: _themeId(json['themeId']) ?? defaults.themeId,
      locale: _locale(json['locale']) ?? defaults.locale,
      confirmUnsavedChanges: json['confirmUnsavedChanges'] is bool
          ? json['confirmUnsavedChanges']! as bool
          : defaults.confirmUnsavedChanges,
      gridSnap: json['gridSnap'] is bool
          ? json['gridSnap']! as bool
          : defaults.gridSnap,
      previewAspectRatio:
          _aspectRatio(json['previewAspectRatio']) ??
          defaults.previewAspectRatio,
      defaultScenePath: json['defaultScenePath'] is String
          ? json['defaultScenePath']! as String
          : defaults.defaultScenePath,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EditorSettings &&
        other.themeId == themeId &&
        other.locale == locale &&
        other.confirmUnsavedChanges == confirmUnsavedChanges &&
        other.gridSnap == gridSnap &&
        other.previewAspectRatio == previewAspectRatio &&
        other.defaultScenePath == defaultScenePath;
  }

  @override
  int get hashCode => Object.hash(
    themeId,
    locale,
    confirmUnsavedChanges,
    gridSnap,
    previewAspectRatio,
    defaultScenePath,
  );
}

EditorThemeId? _themeId(Object? value) {
  if (value is! String) {
    return null;
  }
  for (final id in EditorThemeId.values) {
    if (id.name == value) {
      return id;
    }
  }
  return null;
}

double? _aspectRatio(Object? value) {
  if (value is! num) {
    return null;
  }
  final ratio = value.toDouble();
  return editorAspectRatios.containsValue(ratio) ? ratio : null;
}

String? _locale(Object? value) {
  if (value is! String) {
    return null;
  }
  for (final locale in editorLocales) {
    if (locale.code == value) {
      return value;
    }
  }
  return null;
}
