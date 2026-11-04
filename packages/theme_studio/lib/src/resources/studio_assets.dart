import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'studio_shader_compiler.dart';

enum StudioAssetKind { image, svg, font, material, audio, shader, other }

StudioAssetKind getStudioAssetKind(String path) {
  final lower = path.toLowerCase();
  final extension = lower.split('.').last;
  if (const {'ttf', 'otf', 'woff', 'woff2'}.contains(extension)) {
    return StudioAssetKind.font;
  }
  if (extension == 'svg') return StudioAssetKind.svg;
  if (const {'frag', 'vert', 'glsl'}.contains(extension)) {
    return StudioAssetKind.shader;
  }
  if (const {'wav', 'ogg', 'mp3', 'flac', 'aac'}.contains(extension)) {
    return StudioAssetKind.audio;
  }
  if (const {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'}.contains(extension)) {
    return lower.contains('/textures/') || lower.contains('/materials/')
        ? StudioAssetKind.material
        : StudioAssetKind.image;
  }
  return StudioAssetKind.other;
}

/// Imports into the scene's theme package so saved scene references remain
/// portable. The manifest keeps its comments and existing asset declarations.
class StudioAssets {
  StudioAssets({required this.directory, required this.packageName});

  final Directory directory;
  final String packageName;
  late final shaderCompiler = StudioShaderCompiler(directory: directory);

  Future<ui.FragmentProgram> loadShaderProgram(String asset) {
    final file = findFile(asset);
    return file == null
        ? ui.FragmentProgram.fromAsset(asset)
        : shaderCompiler.loadFile(asset, file);
  }

  /// A standalone JSON keeps the host theme's assets. Stop at the nearest
  /// package boundary so it cannot inherit an unrelated ancestor's theme.
  static StudioAssets? findForScene(File scene) {
    var directory = File(scene.resolveSymbolicLinksSync()).parent;
    while (true) {
      final manifest = File('${directory.path}/pubspec.yaml');
      if (manifest.existsSync()) {
        final root = YamlEditor(manifest.readAsStringSync()).parseAt([]).value;
        final packageName = root is Map ? root['name'] : null;
        if (packageName is! String || !packageName.startsWith('theme_')) {
          return null;
        }
        return StudioAssets(directory: directory, packageName: packageName);
      }
      final parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
  }

  String importFile(
    File source, {
    bool shader = false,
    Directory? targetDirectory,
  }) {
    final target = _getAvailableAssetFile(
      source.uri.pathSegments.last,
      parent: targetDirectory,
    );
    final relative = target.path
        .substring(directory.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    final manifest = File('${directory.path}/pubspec.yaml');
    final original = manifest.readAsStringSync();
    final updated = _getRegisteredManifest(original, relative, shader: shader);
    target.parent.createSync(recursive: true);
    _writeImport(source, target, manifest, original, updated);
    return 'packages/$packageName/$relative';
  }

  File _getAvailableAssetFile(String name, {Directory? parent}) {
    if (name.contains('..')) {
      throw const FormatException('Asset names cannot contain "..".');
    }
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    if (parent != null) {
      final root = directory.resolveSymbolicLinksSync();
      final target = parent.resolveSymbolicLinksSync();
      if (target != root &&
          !target.startsWith('$root${Platform.pathSeparator}')) {
        throw const FormatException(
          'Shader sources must stay inside the current theme.',
        );
      }
    }
    final assets = parent?.path ?? '${directory.path}/assets';
    var target = File('$assets/$name');
    var suffix = 2;
    while (FileSystemEntity.typeSync(target.path) !=
        FileSystemEntityType.notFound) {
      target = File('$assets/$stem-${suffix++}$extension');
    }
    return target;
  }

  String _getRegisteredManifest(
    String original,
    String relative, {
    bool shader = false,
  }) {
    final yaml = YamlEditor(original);
    final root = yaml.parseAt([]).value as Map;
    final flutter = root['flutter'] as Map?;
    final section = shader ? 'shaders' : 'assets';
    final entries = (flutter?[section] as List?) ?? [];
    if ((!shader && entries.contains('assets/')) ||
        entries.contains(relative)) {
      return original;
    }
    if (flutter == null) {
      yaml.update(
        ['flutter'],
        {
          section: [relative],
        },
      );
    } else {
      yaml.update(['flutter', section], [...entries, relative]);
    }
    return yaml.toString();
  }

  void _writeImport(
    File source,
    File target,
    File manifest,
    String originalManifest,
    String updatedManifest,
  ) {
    // Stage both writes before exposing either destination. If manifest update
    // fails, remove our new asset rather than leave an unregistered import.
    final staging = directory.createTempSync('.studio-import-');
    var copied = false;
    try {
      final stagedAsset = source.copySync('${staging.path}/asset');
      final stagedManifest = File('${staging.path}/pubspec.yaml')
        ..writeAsStringSync(updatedManifest, flush: true);
      if (manifest.readAsStringSync() != originalManifest) {
        throw const FileSystemException(
          'Theme manifest changed during import.',
        );
      }
      stagedAsset.renameSync(target.path);
      copied = true;
      if (updatedManifest != originalManifest) {
        stagedManifest.renameSync(manifest.path);
      }
    } on Object {
      if (copied) target.deleteSync();
      rethrow;
    } finally {
      staging.deleteSync(recursive: true);
    }
  }

  List<String> getAssets() {
    final files = <String>{};
    final directories = <String>{'assets/'};
    final root =
        YamlEditor(File('${directory.path}/pubspec.yaml').readAsStringSync())
                .parseAt([])
                .value
            as Map;
    final flutter = root['flutter'] as Map?;
    final declared = <String>[
      for (final entry in flutter?['assets'] as List? ?? const [])
        if (entry is String)
          entry
        else if (entry is Map && entry['path'] is String)
          entry['path'] as String,
      for (final shader in flutter?['shaders'] as List? ?? const [])
        if (shader is String) shader,
      for (final family in flutter?['fonts'] as List? ?? const [])
        for (final font in (family as Map)['fonts'] as List)
          (font as Map)['asset'] as String,
    ];
    for (final path in declared) {
      if (path.contains('..') || path.startsWith('/')) continue;
      if (path.endsWith('/')) {
        directories.add(path);
      } else {
        final file = File('${directory.path}/$path');
        if (file.existsSync()) files.add(file.path);
      }
    }
    for (final path in directories) {
      final folder = Directory(
        '${directory.path}/${path.replaceFirst(RegExp(r'/+$'), '')}',
      );
      if (folder.existsSync()) {
        files.addAll(
          folder
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .map((file) => file.path),
        );
      }
    }
    return files.map((path) {
      final relative = path
          .substring(directory.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      return 'packages/$packageName/$relative';
    }).toList()..sort();
  }

  File? findFile(String asset) {
    final prefix = 'packages/$packageName/';
    if (asset.startsWith(prefix)) {
      return File('${directory.path}/${asset.substring(prefix.length)}');
    }
    if (asset.startsWith('assets/')) {
      return File('${directory.path}/$asset');
    }
    return null;
  }

  ImageProvider getImageProvider(String asset) {
    final file = findFile(asset);
    if (file != null) return FileImage(file);
    return AssetImage(asset);
  }

  Future<String> loadTextAsset(String asset) {
    final file = findFile(asset);
    return file == null ? rootBundle.loadString(asset) : file.readAsString();
  }

  Future<ByteData> loadBytes(String asset) async {
    final file = findFile(asset);
    if (file == null) return rootBundle.load(asset);
    return ByteData.sublistView(await file.readAsBytes());
  }

  Future<String> loadFontPreview(String asset) async {
    final file = findFile(asset);
    final stat = await file?.stat();
    final key =
        '${file?.absolute.path ?? asset}:${stat?.modified.microsecondsSinceEpoch}:${stat?.size}';
    return registerSceneFont(
      source: file?.absolute.path ?? asset,
      revision: key,
      asset: asset,
      loadBytes: () => loadBytes(asset),
    );
  }
}
