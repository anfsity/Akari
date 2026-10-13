import 'package:theme_sdk/theme_sdk.dart';

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
}
