import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'theme_project.dart';

void createThemeHost({
  required Directory repoRoot,
  required ThemePackage theme,
  required Directory output,
  required bool preview,
  Map<String, Object?> devDependencies = const {},
}) {
  output.createSync(recursive: true);
  final lib = Directory('${output.path}/lib')..createSync(recursive: true);
  final sources = Directory('${repoRoot.path}/lib')
      .listSync(followLinks: false);
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
      'dbus': platform['dependencies']['dbus'],
      'greeter_ui': {'path': '${repoRoot.path}/packages/greeter_ui'},
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
