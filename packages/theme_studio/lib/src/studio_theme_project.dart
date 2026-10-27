import 'dart:io';
import 'dart:ui' show Color;

import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_project/theme_project.dart';

import 'scene_editor.dart';
import 'studio_assets.dart';

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

  Future<StudioThemeProject> createTheme({
    required String packageName,
    required String destination,
    required SceneDocument document,
    required StudioAssets assets,
  }) async {
    final references = {
      if (document.background.asset != null) document.background.asset!,
      ...document.themeProperties.values,
      for (final node in document.nodes) ...node.properties.values,
      for (final node in document.nodes)
        if (node.asset != null) node.asset!.path,
    };
    final files = <String, File>{};
    for (final reference in references) {
      final file = assets.findFile(reference);
      if (file != null && await file.exists()) files[reference] = file;
    }
    final result = await createThemeProject(
      source: Directory(directory),
      destination: Directory(destination),
      packageName: packageName,
      document: document,
      assetFiles: files,
    );
    return StudioThemeProject(
      packageName: result.packageName,
      directory: result.directory.path,
      scenePaths: findThemeSceneFiles(result.directory)
          .map((file) => file.path)
          .toList(),
      themeBuilder: ({Color? seed, SceneDocument? document}) => themeBuilder(
        seed: seed,
        document: document ?? result.document,
      ).copyWith(id: result.packageName.substring('theme_'.length)),
    );
  }

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
