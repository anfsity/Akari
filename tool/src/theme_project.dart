import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:yaml/yaml.dart';

const _themePackagePrefix = 'theme_';

class ThemePackage {
  const ThemePackage({
    required this.packageName,
    required this.builderName,
    required this.directory,
  });

  final String packageName;
  final String builderName;
  final Directory directory;
}

ThemePackage getThemePackage(Directory projectDirectory) {
  final directory = Directory(projectDirectory.resolveSymbolicLinksSync());
  final manifest = File(_join(directory.path, 'pubspec.yaml'));
  final pubspec = loadYaml(manifest.readAsStringSync());
  final packageName = pubspec is YamlMap ? pubspec['name'] : null;
  if (packageName is! String || !packageName.startsWith(_themePackagePrefix)) {
    throw FormatException('Theme package names must start with theme_.');
  }
  final themeName = packageName.substring(_themePackagePrefix.length);
  if (!RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$').hasMatch(themeName)) {
    throw FormatException(
      'Theme package $packageName must use a lowercase underscore name.',
    );
  }
  final libDirectory = Directory(_join(directory.path, 'lib'));
  final entrypoint = File(_join(libDirectory.path, 'theme.dart'));
  final sceneFiles = libDirectory.existsSync()
      ? libDirectory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.scene.json'))
            .toList()
      : const <File>[];
  if (!entrypoint.existsSync() || sceneFiles.isEmpty) {
    throw FormatException(
      '$packageName must contain lib/theme.dart and a .scene.json document.',
    );
  }
  final builderName = _getBuilderName(themeName);
  if (!RegExp(r'\b' + RegExp.escape(builderName) + r'\s*\(')
      .hasMatch(entrypoint.readAsStringSync())) {
    throw FormatException(
      '$packageName must export $builderName() from lib/theme.dart.',
    );
  }
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

String _getBuilderName(String themeName) {
  final words = themeName.split('_');
  final pascalName = words
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join();
  return 'build${pascalName}Theme';
}

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

String getThemeHostDirectory(ThemePackage theme, {required bool preview}) =>
    'build/tool/hosts/${getThemeCacheKey(theme)}/${preview ? 'demo' : 'real'}';

String getLinuxExecutablePath(String hostDirectory, String buildMode) {
  final architecture = switch (Abi.current()) {
    Abi.linuxX64 => 'x64',
    Abi.linuxArm64 => 'arm64',
    _ => throw UnsupportedError('Linux builds require an x64 or arm64 host.'),
  };
  return '$hostDirectory/build/linux/$architecture/$buildMode/bundle/greeter';
}
