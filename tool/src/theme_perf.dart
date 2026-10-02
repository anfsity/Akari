import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'theme_project.dart';

/// Only the transport is shared. Themes own their commands, test journeys,
/// metrics, baselines, and the contents of every reported artifact.
List<String> getThemePerfCommand(ThemePackage theme, String operation) {
  final manifest = loadYaml(
    File('${theme.directory.path}/pubspec.yaml').readAsStringSync(),
  ) as YamlMap;
  final perf = manifest['perf'];
  if (perf == null) {
    throw FormatException('${theme.packageName} does not support $operation.');
  }
  if (perf is! YamlMap || perf['version'] != 1) {
    throw const FormatException('Theme perf configuration requires version 1.');
  }
  final command = perf[operation];
  if (command == null) {
    throw FormatException('${theme.packageName} does not support $operation.');
  }
  if (command is! YamlList ||
      command.isEmpty ||
      command.any((argument) => argument is! String) ||
      (command.first as String).isEmpty) {
    throw FormatException('perf.$operation must be a non-empty command array.');
  }
  return command.cast<String>().toList();
}

Future<Map<String, String>> getThemePerfArtifacts(File manifest) async {
  final result = jsonDecode(await manifest.readAsString());
  if (result is! Map<String, dynamic> || result['version'] != 1) {
    throw const FormatException('Theme perf result requires version 1.');
  }
  final artifacts = result['artifacts'];
  if (artifacts is! List) {
    throw const FormatException(
      'Theme perf result requires an artifacts array.',
    );
  }
  final outputPath = await manifest.parent.resolveSymbolicLinks();
  final paths = <String, String>{};
  for (final artifact in artifacts) {
    if (artifact is! Map<String, dynamic>) {
      throw const FormatException('Each perf artifact must be an object.');
    }
    final name = artifact['name'];
    final path = artifact['path'];
    if (name is! String || name.isEmpty || paths.containsKey(name)) {
      throw const FormatException(
        'Perf artifact names must be non-empty and unique.',
      );
    }
    if (path is! String || path.isEmpty || File(path).isAbsolute) {
      throw const FormatException(
        'Perf artifact paths must be relative to the output directory.',
      );
    }
    final file = File('$outputPath/$path');
    final resolvedPath = await file.resolveSymbolicLinks();
    if (!resolvedPath.startsWith('$outputPath${Platform.pathSeparator}')) {
      throw FormatException(
        'Perf artifact escapes the output directory: $path',
      );
    }
    paths[name] = resolvedPath;
  }
  return paths;
}
