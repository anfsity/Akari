import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'theme_project.dart';

/// Assembles a reusable executable host with a direct import of one theme.
/// Shared Dart sources are linked for live edits; native sources and generated
/// entrypoints are updated only when content changes to retain build caches.
/// Dependency selection belongs to this host, not the platform's manifest.
void createThemeHost({
  required Directory repoRoot,
  required ThemePackage theme,
  required Directory output,
  required bool preview,
  bool studio = false,
  Map<String, Object?> devDependencies = const {},
}) {
  output.createSync(recursive: true);
  final lib = Directory('${output.path}/lib')..createSync(recursive: true);
  final sources = studio
      ? const <FileSystemEntity>[]
      : Directory('${repoRoot.path}/lib').listSync(followLinks: false);
  final names = {'main.dart'};
  for (final source in sources) {
    final name = source.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (name == 'main.dart') continue;
    names.add(name);
    final link = Link('${lib.path}/$name');
    if (!link.existsSync()) link.createSync(source.path);
  }
  for (final entity in lib.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (!names.contains(name)) entity.deleteSync(recursive: true);
  }
  _syncDirectory(
    Directory('${repoRoot.path}/linux'),
    Directory('${output.path}/linux'),
  );

  final platform = loadYaml(
    File('${repoRoot.path}/pubspec.yaml').readAsStringSync(),
  ) as YamlMap;
  final manifest = {
    'name': 'greeter',
    'publish_to': 'none',
    'version': platform['version'],
    'environment': platform['environment'],
    'dependencies': {
      'flutter': {'sdk': 'flutter'},
      if (!studio) ...{
        'dbus': platform['dependencies']['dbus'],
        'greeter_ui': {'path': '${repoRoot.path}/packages/greeter_ui'},
      },
      if (studio)
        'theme_studio': {'path': '${repoRoot.path}/packages/theme_studio'},
      'theme_sdk': {'path': '${repoRoot.path}/packages/theme_sdk'},
      theme.packageName: {'path': theme.directory.path},
    },
    'flutter': {'uses-material-design': true},
    if (devDependencies.isNotEmpty) 'dev_dependencies': devDependencies,
  };
  _writeIfChanged(
    File('${output.path}/pubspec.yaml'),
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );

  if (studio) {
    final scenes = findThemeSceneFiles(theme.directory);
    _writeIfChanged(File('${output.path}/lib/main.dart'), '''
import 'package:flutter/widgets.dart';
import 'package:theme_studio/theme_studio.dart';
import 'package:${theme.packageName}/theme.dart' show ${theme.builderName};

void main() {
  runApp(ThemeStudioApp(
    themeBuilder: ${theme.builderName},
    scenePaths: [${scenes.map((file) => jsonEncode(file.path).replaceAll(r'$', r'\$')).join(', ')}],
  ));
}
''');
    return;
  }

  _writeIfChanged(File('${output.path}/lib/main.dart'), '''
import 'package:flutter/widgets.dart';
import 'package:${theme.packageName}/theme.dart' show ${theme.builderName};

import 'app/app.dart';
${preview ? '' : "import 'infrastructure/preferences/file_session_store.dart';"}

void main() {
  runApp(
    MyApp(
      themeBuilder: ${theme.builderName},
      ${preview ? '' : 'sessionStore: FileSessionStore(),'}
    ),
  );
}
''');
}

// These belong to Flutter in each host. Copying the root's plugin registrants
// or ephemeral files would substitute another project's dependency/build state.
const _flutterGeneratedNames = {
  'ephemeral',
  'generated_plugins.cmake',
  'generated_plugin_registrant.cc',
  'generated_plugin_registrant.h',
};

void _syncDirectory(Directory source, Directory target) {
  target.createSync(recursive: true);
  final names = <String>{};
  for (final entity in source.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
    names.add(name);
    if (_flutterGeneratedNames.contains(name)) continue;
    if (entity is Directory) {
      _syncDirectory(entity, Directory('${target.path}/$name'));
    } else if (entity is File) {
      final file = File('${target.path}/$name');
      final bytes = entity.readAsBytesSync();
      if (!file.existsSync() || !_isSameBytes(bytes, file.readAsBytesSync())) {
        file.writeAsBytesSync(bytes);
      }
    }
  }
  for (final entity in target.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (!names.contains(name) && !_flutterGeneratedNames.contains(name)) {
      entity.deleteSync(recursive: true);
    }
  }
}

bool _isSameBytes(List<int> source, List<int> target) {
  if (source.length != target.length) return false;
  for (var index = 0; index < source.length; index++) {
    if (source[index] != target[index]) return false;
  }
  return true;
}

void _writeIfChanged(File file, String content) {
  if (!file.existsSync() || file.readAsStringSync() != content) {
    file.writeAsStringSync(content);
  }
}
