import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scene_codegen/scene_codegen.dart';
import 'package:scene_schema/scene_schema.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'project.dart';

class SynthesizedTheme {
  const SynthesizedTheme({
    required this.directory,
    required this.packageName,
    required this.document,
  });

  final Directory directory;
  final String packageName;
  final SceneDocument document;
  String get scenePath =>
      p.join(directory.path, 'lib', 'composition.scene.json');
}

/// Copies authored implementation and resources, then binds a new public
/// entrypoint to the edited scene. No source file is changed and the complete
/// target is staged before it becomes a discoverable project.
Future<SynthesizedTheme> createThemeProject({
  required Directory source,
  required Directory destination,
  required String packageName,
  required SceneDocument document,
  Map<String, File> assetFiles = const {},
}) async {
  final builderName = getThemeBuilderName(packageName);
  final sourceRoot = await source.resolveSymbolicLinks();
  final target = await _getPhysicalTarget(destination);
  if (p.equals(sourceRoot, target) ||
      p.isWithin(sourceRoot, target) ||
      p.isWithin(target, sourceRoot)) {
    throw const FileSystemException(
      'Choose a destination outside the source theme.',
    );
  }
  await _validateDestination(target);
  final manifestText = await File(p.join(sourceRoot, 'pubspec.yaml'))
      .readAsString();
  final manifest = loadYaml(manifestText);
  if (manifest is! Map || manifest['name'] is! String) {
    throw const FormatException('Source theme must declare its package name.');
  }
  final sourceName = manifest['name'] as String;
  final sourceBuilder = getThemeBuilderName(sourceName);
  validateThemeEntrypoint(
    await File(p.join(sourceRoot, 'lib', 'theme.dart')).readAsString(),
    sourceBuilder,
    sourceName,
  );
  // Validate the current document before creating a destination or copying data.
  final validated = decodeSceneDocument(encodeSceneDocument(document));
  final parent = Directory(p.dirname(target));
  await parent.create(recursive: true);
  final staging = await parent.createTemp('.akari-theme-');
  try {
    await _copySourceProject(
      sourceRoot,
      staging,
      manifest,
      sourceName,
      packageName,
    );
    final sourceEntrypoint = File(p.join(staging.path, 'lib', 'theme.dart'));
    var localSource = 'source_theme.dart';
    var suffix = 2;
    while (await File(p.join(staging.path, 'lib', localSource)).exists()) {
      localSource = 'source_theme_${suffix++}.dart';
    }
    await sourceEntrypoint.rename(p.join(staging.path, 'lib', localSource));

    final mappings = await _copyReferencedAssets(
      validated,
      assetFiles,
      sourceRoot,
      staging,
      packageName,
    );
    String rewriteAsset(String value) =>
        mappings[value] ??
        _rewriteSelfReferences(value, sourceName, packageName);
    final composed = validated.copyWith(
      background: validated.background.asset == null
          ? validated.background
          : validated.background.copyWith(
              asset: rewriteAsset(validated.background.asset!),
            ),
      themeProperties: validated.themeProperties.map(
        (key, value) => MapEntry(key, rewriteAsset(value)),
      ),
      nodes: [
        for (final node in validated.nodes)
          node.copyWith(
            properties: node.properties.map(
              (key, value) => MapEntry(key, rewriteAsset(value)),
            ),
          ),
      ],
    );
    await File(p.join(staging.path, 'lib', 'composition.scene.json'))
        .writeAsString('${encodeSceneDocument(composed)}\n');
    await File(p.join(staging.path, 'pubspec.yaml')).writeAsString(
      _getProjectManifest(
        manifestText,
        manifest,
        sourceRoot,
        target,
        packageName,
        mappings.values,
      ),
    );
    final sceneGetter = getSceneDocumentVariableName(composed.id);
    final themeId = packageName.substring('theme_'.length);
    await File(p.join(staging.path, 'lib', 'theme.dart')).writeAsString('''
import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'composition.scene.g.dart' as composition;
import '$localSource' as preset;
export '$localSource';

ThemeDefinition $builderName({Color? seed, SceneDocument? document}) =>
    preset.$sourceBuilder(
      seed: seed,
      document: document ?? composition.$sceneGetter,
    ).copyWith(id: '$themeId');
''');
    await _generateSceneSources(staging);
    await _writeProjectReadme(staging, themeId, sourceName);
    await _validateDestination(target);
    await staging.rename(target);
    return SynthesizedTheme(
      directory: Directory(target),
      packageName: packageName,
      document: composed,
    );
  } finally {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}

Future<void> _validateDestination(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw FileSystemException('Destination already exists.', path);
  }
}

Future<String> _getPhysicalTarget(Directory destination) async {
  var parent = Directory(p.dirname(p.normalize(destination.absolute.path)));
  final missing = <String>[p.basename(p.normalize(destination.absolute.path))];
  while (!await parent.exists()) {
    missing.add(p.basename(parent.path));
    parent = parent.parent;
  }
  return p.joinAll([await parent.resolveSymbolicLinks(), ...missing.reversed]);
}

Set<String> _getSourceRoots(Map manifest) {
  final roots = {
    'lib',
    'assets',
    'test',
    'perf',
    'build.yaml',
    'analysis_options.yaml',
  };
  final flutter = manifest['flutter'];
  if (flutter is! Map) return roots;
  final resources = <String>[
    for (final asset in flutter['assets'] as List? ?? [])
      if (asset is String)
        asset
      else if (asset is Map && asset['path'] is String)
        asset['path'] as String,
    for (final font in flutter['fonts'] as List? ?? [])
      for (final item in (font as Map)['fonts'] as List? ?? [])
        (item as Map)['asset'] as String,
    ...?(flutter['shaders'] as List?)?.cast<String>(),
    ...?(flutter['licenses'] as List?)?.cast<String>(),
  ];
  for (final resource in resources) {
    final path = p.normalize(resource);
    if (p.isAbsolute(path) || p.split(path).first == '..') {
      throw FormatException(
        'Theme resources must stay inside their package: $resource',
      );
    }
    roots.add(p.split(path).first);
  }
  return roots;
}

Future<void> _copyEntry(
  String source,
  String target,
  String sourceName,
  String targetName,
  Set<String> ancestors,
) async {
  final name = p.basename(source);
  if ({
        '.git',
        '.dart_tool',
        '.fvm',
        'build',
        'target',
        'node_modules',
        '__pycache__',
      }.contains(name) ||
      name.endsWith('.scene.g.dart')) {
    return;
  }
  final type = await FileSystemEntity.type(source, followLinks: true);
  if (type == FileSystemEntityType.directory) {
    final physical = await Directory(source).resolveSymbolicLinks();
    if (ancestors.contains(physical)) {
      throw FileSystemException('Cyclic directory link in theme.', source);
    }
    await Directory(target).create(recursive: true);
    await for (final entry in Directory(source).list(followLinks: false)) {
      await _copyEntry(
        entry.path,
        p.join(target, p.basename(entry.path)),
        sourceName,
        targetName,
        {...ancestors, physical},
      );
    }
    return;
  }
  if (type != FileSystemEntityType.file) {
    throw FileSystemException('Unreadable theme resource.', source);
  }
  await File(target).parent.create(recursive: true);
  if (source.endsWith('.dart') || source.endsWith('.scene.json')) {
    await File(target).writeAsString(
      _rewriteSelfReferences(
        await File(source).readAsString(),
        sourceName,
        targetName,
      ),
    );
  } else {
    await File(source).copy(target);
  }
}

String _rewriteSelfReferences(
  String value,
  String sourceName,
  String targetName,
) => value
    .replaceAll('package:$sourceName/', 'package:$targetName/')
    .replaceAll('packages/$sourceName/', 'packages/$targetName/');

Future<void> _copySourceProject(
  String sourceRoot,
  Directory staging,
  Map manifest,
  String sourceName,
  String packageName,
) async {
  final roots = _getSourceRoots(manifest);
  await for (final entry in Directory(sourceRoot).list(followLinks: false)) {
    final name = p.basename(entry.path);
    if (!roots.contains(name) &&
        !name.startsWith('README') &&
        !name.startsWith('LICENSE')) {
      continue;
    }
    await _copyEntry(
      entry.path,
      p.join(staging.path, name),
      sourceName,
      packageName,
      {},
    );
  }
}

Future<Map<String, String>> _copyReferencedAssets(
  SceneDocument validated,
  Map<String, File> assetFiles,
  String sourceRoot,
  Directory staging,
  String packageName,
) async {
  final mappings = <String, String>{};
  final references = {
    if (validated.background.asset != null) validated.background.asset!,
    ...validated.themeProperties.values,
    for (final node in validated.nodes) ...node.properties.values,
  };
  for (final entry in assetFiles.entries) {
    if (!references.contains(entry.key)) continue;
    final physical = await entry.value.resolveSymbolicLinks();
    if (p.isWithin(sourceRoot, physical)) {
      final relative = p
          .relative(physical, from: sourceRoot)
          .split(p.separator)
          .join('/');
      if (await File(p.join(staging.path, relative)).exists()) {
        mappings[entry.key] = 'packages/$packageName/$relative';
        continue;
      }
    }
    final imported = Directory(p.join(staging.path, 'assets', 'composed'));
    await imported.create(recursive: true);
    var fileName = p.basename(physical);
    var index = 2;
    while (await File(p.join(imported.path, fileName)).exists()) {
      fileName =
          '${p.basenameWithoutExtension(physical)}-${index++}${p.extension(physical)}';
    }
    await File(physical).copy(p.join(imported.path, fileName));
    mappings[entry.key] = 'packages/$packageName/assets/composed/$fileName';
  }
  return mappings;
}

String _getProjectManifest(
  String manifestText,
  Map manifest,
  String sourceRoot,
  String target,
  String packageName,
  Iterable<String> assetReferences,
) {
  final yaml = YamlEditor(manifestText);
  yaml.update(['name'], packageName);
  for (final section in [
    'dependencies',
    'dev_dependencies',
    'dependency_overrides',
  ]) {
    final dependencies = manifest[section];
    if (dependencies is! Map) continue;
    for (final entry in dependencies.entries) {
      final value = entry.value;
      if (value is Map && value['path'] is String) {
        final physical = p.normalize(
          p.join(sourceRoot, value['path'] as String),
        );
        yaml.update([
          section,
          entry.key,
          'path',
        ], p.relative(physical, from: target));
      }
    }
  }
  final metadata = manifest['akari'];
  if (metadata != null && metadata is! Map) {
    throw const FormatException('akari project metadata must be a map.');
  }
  yaml.update(
    ['akari'],
    {...?metadata as Map?, 'scene': 'lib/composition.scene.json'},
  );
  if (assetReferences.isNotEmpty) {
    final flutter = manifest['flutter'] as Map? ?? {};
    final assets = List<Object?>.of(flutter['assets'] as List? ?? []);
    for (final reference in assetReferences) {
      final relative = reference.substring('packages/$packageName/'.length);
      final parent = '${p.posix.dirname(relative)}/';
      if (!assets.any(
        (asset) =>
            asset == relative ||
            asset == parent ||
            (asset is Map &&
                (asset['path'] == relative || asset['path'] == parent)),
      )) {
        assets.add(relative);
      }
    }
    yaml.update(['flutter'], {...flutter, 'assets': assets});
  }
  return yaml.toString();
}

Future<void> _generateSceneSources(Directory staging) async {
  await for (final file in Directory(
    p.join(staging.path, 'lib'),
  ).list(recursive: true, followLinks: false)) {
    if (file is File && file.path.endsWith('.scene.json')) {
      await File(
        file.path.replaceFirst(RegExp(r'\.scene\.json$'), '.scene.g.dart'),
      ).writeAsString(generateScene(await file.readAsString()));
    }
  }
}

Future<void> _writeProjectReadme(
  Directory staging,
  String themeId,
  String sourceName,
) async {
  final originalReadme = File(p.join(staging.path, 'README.md'));
  final notes = await originalReadme.exists()
      ? await originalReadme.readAsString()
      : '';
  await originalReadme.writeAsString('''# $themeId

Created from $sourceName in Theme Studio. This project owns its scene, code,
fonts and resources. From this directory:

```sh
akari run studio --theme .
akari run --theme .
akari build --theme .
```

$notes''');
}
