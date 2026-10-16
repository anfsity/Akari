import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'project.dart';
import 'model.dart';

/// Assembles a reusable executable host with direct imports of compiled themes.
/// Shared Dart sources are linked for live edits; native sources and generated
/// entrypoints are updated only when content changes to retain build caches.
/// Dependency selection belongs to this host, not the platform's manifest.
void createThemeHost({
  required Directory repoRoot,
  required ThemePackage theme,
  required Directory output,
  required ThemeHostKind kind,
  List<ThemePackage>? studioThemes,
  Map<String, Object?> devDependencies = const {},
}) {
  final studio = kind == ThemeHostKind.studio;
  final preview = kind == ThemeHostKind.preview;
  final themes = studio
      ? studioThemes ?? findStudioThemePackages(repoRoot, theme)
      : [theme];
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
  if (preview) {
    names.add('akari_preview');
    final link = Link('${lib.path}/akari_preview');
    if (FileSystemEntity.typeSync(link.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      link.createSync('${repoRoot.path}/tool/preview');
    }
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
      for (final project in themes)
        project.packageName: {'path': project.directory.path},
    },
    'flutter': {'uses-material-design': true},
    if (preview || devDependencies.isNotEmpty)
      'dev_dependencies': {
        if (preview) ...{
          'flutter_test': {'sdk': 'flutter'},
          'integration_test': {'sdk': 'flutter'},
        },
        ...devDependencies,
      },
  };
  _writeIfChanged(
    File('${output.path}/pubspec.yaml'),
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );

  if (studio) {
    final imports = [
      for (var index = 0; index < themes.length; index++)
        "import 'package:${themes[index].packageName}/theme.dart' as theme$index;",
    ].join('\n');
    final projects = [
      for (var index = 0; index < themes.length; index++)
        '''    StudioThemeProject(
      themeBuilder: theme$index.${themes[index].builderName},
      directory: ${jsonEncode(themes[index].directory.path).replaceAll(r'$', r'\$')},
      packageName: ${jsonEncode(themes[index].packageName)},
      scenePaths: [${findThemeSceneFiles(themes[index].directory).map((file) => jsonEncode(file.path).replaceAll(r'$', r'\$')).join(', ')}],
    ),''',
    ].join('\n');
    _writeIfChanged(File('${output.path}/lib/main.dart'), '''
import 'package:flutter/widgets.dart';
import 'package:theme_studio/theme_studio.dart';
$imports

void main() {
  runApp(ThemeStudioApp(
    initialThemePackageName: ${jsonEncode(theme.packageName)},
    projects: [
$projects
    ],
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
  if (preview) {
    final integration = Directory('${output.path}/integration_test')
      ..createSync(recursive: true);
    _writeIfChanged(File('${integration.path}/preview_test.dart'), '''
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:greeter/akari_preview/journey.dart';
import 'package:greeter/akari_preview/scenarios.dart';
import 'package:${theme.packageName}/theme.dart' show ${theme.builderName};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const selected = String.fromEnvironment('AKARI_PREVIEW_SCENARIO', defaultValue: 'all');
  const resultPath = String.fromEnvironment('AKARI_PREVIEW_RESULT');
  final results = <String, String>{};
  for (final scenario in previewScenarioNames.where((name) => selected == 'all' || selected == name)) {
    testWidgets(scenario, (tester) async {
      try {
        await runPreviewScenario(tester, ${theme.builderName}, scenario);
        results[scenario] = 'passed';
      } catch (_) {
        results[scenario] = 'failed';
        rethrow;
      } finally {
        final file = File(resultPath);
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(results));
      }
    }, timeout: const Timeout(Duration(seconds: 45)));
  }
}
''');
  }
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
