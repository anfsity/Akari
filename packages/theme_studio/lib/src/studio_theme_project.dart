import 'dart:io';

import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';

/// A compiled theme and its authoring files travel together when Studio switches
/// projects. Loading JSON alone cannot substitute a component factory.
class StudioThemeProject {
  const StudioThemeProject({
    required this.packageName,
    required this.directory,
    required this.scenePaths,
    required this.themeBuilder,
  });

  final String packageName;
  final String directory;
  final List<String> scenePaths;
  final ThemeBuilder themeBuilder;

  /// The caller owns the returned editor. Resolve the complete target before
  /// replacing an open session; a rejected theme must not leak its controllers.
  ({SceneEditor editor, ThemeDefinition theme}) createSceneSession(
    String path,
  ) {
    final declarations = themeBuilder();
    final editor = SceneEditor(
      File(path),
      componentCatalog: declarations.componentCatalog,
      presetCatalog: declarations.presetCatalog,
      layout: declarations.layout,
    );
    try {
      return (editor: editor, theme: themeBuilder(document: editor.document));
    } on Object {
      editor.dispose();
      rethrow;
    }
  }
}
