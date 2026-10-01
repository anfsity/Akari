import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'theme_catalog.dart';

void createThemeHost({
  required Directory repoRoot,
  required ThemePackage theme,
  required Directory output,
  required bool preview,
}) {
  output.createSync(recursive: true);
  for (final name in ['lib', 'linux']) {
    _copyDirectory(
      Directory('${repoRoot.path}/$name'),
      Directory('${output.path}/$name'),
    );
  }

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
  };
  File('${output.path}/pubspec.yaml').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );

  File('${output.path}/lib/main.dart').writeAsStringSync('''
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

void _copyDirectory(Directory source, Directory target) {
  target.createSync(recursive: true);
  for (final entity in source.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (entity is Directory) {
      // Flutter regenerates SDK-specific files inside the new host project.
      if (name != 'ephemeral') {
        _copyDirectory(entity, Directory('${target.path}/$name'));
      }
    } else if (entity is File) {
      entity.copySync('${target.path}/$name');
    }
  }
}
