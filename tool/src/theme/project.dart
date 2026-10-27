import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:theme_project/theme_project.dart';
import 'package:yaml/yaml.dart';

import 'model.dart';

export 'package:theme_project/theme_project.dart' show findThemeSceneFiles;

class ThemePackage {
  const ThemePackage({
    required this.packageName,
    required this.builderName,
    required this.directory,
  });

  final String packageName;
  final String builderName;
  final Directory directory;

  String get name => packageName;
}

/// Resolves the physical project path and checks its authoring contract before
/// planning a host build. Canonicalization makes symlink aliases share caches
/// and locks, while separate projects with the same package name stay distinct.
ThemePackage getThemePackage(Directory projectDirectory) {
  final directory = Directory(projectDirectory.resolveSymbolicLinksSync());
  final manifest = File(_join(directory.path, 'pubspec.yaml'));
  final pubspec = loadYaml(manifest.readAsStringSync());
  final packageName = pubspec is YamlMap ? pubspec['name'] : null;
  if (packageName is! String) {
    throw FormatException('Theme package names must start with theme_.');
  }
  final builderName = getThemeBuilderName(packageName);
  final libDirectory = Directory(_join(directory.path, 'lib'));
  final entrypoint = File(_join(libDirectory.path, 'theme.dart'));
  final sceneFiles = findThemeSceneFiles(directory);
  if (!entrypoint.existsSync() || sceneFiles.isEmpty) {
    throw FormatException(
      '$packageName must contain lib/theme.dart and a .scene.json document.',
    );
  }
  validateThemeEntrypoint(
    entrypoint.readAsStringSync(),
    builderName,
    packageName,
  );
  return ThemePackage(
    packageName: packageName,
    builderName: builderName,
    directory: directory,
  );
}

List<ThemePackage> findThemePackages(Directory repoRoot) {
  final themesDirectory = Directory(_join(repoRoot.path, 'themes'));
  final themes = themesDirectory
      .listSync(followLinks: false)
      .whereType<Directory>()
      .where(
        (directory) => File(_join(directory.path, 'pubspec.yaml')).existsSync(),
      )
      .map(getThemePackage)
      .toList();
  themes.sort((left, right) => left.packageName.compareTo(right.packageName));
  final names = <String>{};
  for (final theme in themes) {
    if (!names.add(theme.packageName)) {
      throw StateError('Duplicate theme package name: ${theme.packageName}');
    }
  }
  return themes;
}

/// Studio compiles the repository's presets alongside the selected project.
/// An external project owns its package name, including when it overrides a
/// built-in theme; pub cannot resolve two paths for the same package identity.
List<ThemePackage> findStudioThemePackages(
  Directory repoRoot,
  ThemePackage selected,
) => [
  selected,
  ...findThemePackages(repoRoot)
      .where((theme) => theme.packageName != selected.packageName),
]..sort((left, right) => left.packageName.compareTo(right.packageName));

String _join(String base, String relative) {
  return '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
}

// Encode the canonical path without hashing so same-named external themes
// cannot share a host. Split long paths to stay below filesystem name limits.
String getThemeCacheKey(ThemePackage theme) {
  final encoded = base64Url
      .encode(utf8.encode(theme.directory.path))
      .replaceAll('=', '');
  return [
    for (var start = 0; start < encoded.length; start += 120)
      encoded.substring(
        start,
        start + 120 < encoded.length ? start + 120 : encoded.length,
      ),
  ].join('/');
}

String getThemeHostDirectory(ThemePackage theme, ThemeHostKind kind) =>
    'build/tool/hosts/${getThemeCacheKey(theme)}/${kind.cacheName}';

String getBackendTargetDirectory(BackendMode backend) =>
    'target/akari-${backend.name}';

String getBackendExecutablePath(BackendMode backend, BuildMode mode) =>
    'backend/${getBackendTargetDirectory(backend)}/${mode.rustProfile}/backend';

String getSplashExecutablePath(BuildMode mode) =>
    'build/tool/splash/${mode.rustProfile}/akari-splash';

String getLinuxExecutablePath(String hostDirectory, BuildMode buildMode) {
  final architecture = switch (Abi.current()) {
    Abi.linuxX64 => 'x64',
    Abi.linuxArm64 => 'arm64',
    _ => throw UnsupportedError('Linux builds require an x64 or arm64 host.'),
  };
  return '$hostDirectory/build/linux/$architecture/${buildMode.name}/bundle/greeter';
}
