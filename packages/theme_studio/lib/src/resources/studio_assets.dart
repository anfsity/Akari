import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'confined_path.dart';
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

  String get _rootDirectoryPath => trimTrailingSeparator(directory.path);

  String _getRelativePath(String path) {
    final base = _rootDirectoryPath == Platform.pathSeparator
        ? Platform.pathSeparator
        : '$_rootDirectoryPath${Platform.pathSeparator}';
    return path.substring(base.length).replaceAll(Platform.pathSeparator, '/');
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
    final relative = _getRelativePath(target.path);
    final manifest = File('$_rootDirectoryPath/pubspec.yaml');
    final original = manifest.readAsStringSync();
    final updated = _getRegisteredManifest(original, relative, shader: shader);
    target.parent.createSync(recursive: true);
    _writeImport(source, target, manifest, original, updated);
    return 'packages/$packageName/$relative';
  }

  File _getAvailableAssetFile(String name, {Directory? parent}) {
    if (name.isEmpty ||
        name.startsWith('.') ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('..') ||
        name.contains('\u0000')) {
      throw const FormatException(
        'Asset names must be filenames without path separators or leading dots.',
      );
    }
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    final String assets;
    if (parent == null) {
      assets = '$_rootDirectoryPath/assets';
    } else {
      final root = directory.resolveSymbolicLinksSync();
      if (!parent.existsSync()) {
        throw const FormatException(
          'Shader sources must stay inside the current theme.',
        );
      }
      final target = parent.resolveSymbolicLinksSync();
      if (!isCanonicalPathWithin(root, target)) {
        throw const FormatException(
          'Shader sources must stay inside the current theme.',
        );
      }
      final base = root.endsWith(Platform.pathSeparator)
          ? root
          : '$root${Platform.pathSeparator}';
      final relativeParent = target == root
          ? ''
          : target.substring(base.length);
      assets = relativeParent.isEmpty
          ? _rootDirectoryPath
          : '$_rootDirectoryPath/$relativeParent';
    }
    var target = File('$assets/$name');
    var suffix = 2;
    while (FileSystemEntity.typeSync(target.path, followLinks: false) !=
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
    final root = yaml.parseAt([]).value;
    if (root is! Map) {
      throw const FormatException('Theme pubspec.yaml must be a YAML mapping.');
    }
    final flutter = root['flutter'];
    if (flutter != null && flutter is! Map) {
      throw const FormatException(
        'Theme pubspec.yaml flutter section must be a mapping.',
      );
    }
    final section = shader ? 'shaders' : 'assets';
    final rawEntries = (flutter as Map?)?[section];
    final List<Object?> entries;
    if (rawEntries == null) {
      entries = const <Object?>[];
    } else if (rawEntries is List) {
      entries = rawEntries.cast<Object?>();
    } else {
      throw FormatException(
        'Theme pubspec.yaml flutter.$section must be a list.',
      );
    }
    bool hasEntry(String expected) => entries.any(
      (entry) =>
          entry == expected || (entry is Map && entry['path'] == expected),
    );
    final slash = relative.lastIndexOf('/');
    final parentDirectory = slash >= 0
        ? relative.substring(0, slash + 1)
        : null;
    if ((!shader && parentDirectory != null && hasEntry(parentDirectory)) ||
        hasEntry(relative)) {
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
    final root = YamlEditor(
      File('$_rootDirectoryPath/pubspec.yaml').readAsStringSync(),
    ).parseAt([]).value;
    if (root is! Map) {
      throw const FormatException('Theme pubspec.yaml must be a YAML mapping.');
    }
    final flutterRaw = root['flutter'];
    final flutter = flutterRaw is Map ? flutterRaw : null;
    final rawAssets = flutter?['assets'];
    final rawShaders = flutter?['shaders'];
    final rawFonts = flutter?['fonts'];
    final declared = <String>[
      if (rawAssets is List)
        for (final entry in rawAssets)
          if (entry is String)
            entry
          else if (entry is Map && entry['path'] is String)
            entry['path'] as String,
      if (rawShaders is List)
        for (final shader in rawShaders)
          if (shader is String) shader,
      if (rawFonts is List)
        for (final family in rawFonts)
          if (family is Map && family['fonts'] is List)
            for (final font in family['fonts'] as List)
              if (font is Map && font['asset'] is String)
                font['asset'] as String,
    ];
    final rootPath = directory.resolveSymbolicLinksSync();
    for (final path in declared) {
      if (path.endsWith('/')) {
        final trimmed = path.replaceFirst(RegExp(r'/+$'), '');
        if (trimmed.isNotEmpty && parseSafeRelativeSegments(trimmed) != null) {
          directories.add(path);
        }
      } else {
        final file = findConfinedFile(directory, path);
        if (file != null && file.existsSync()) files.add(file.path);
      }
    }
    for (final path in directories) {
      final folder = Directory(
        '$_rootDirectoryPath/${path.replaceFirst(RegExp(r'/+$'), '')}',
      );
      if (folder.existsSync() &&
          isCanonicalPathWithin(rootPath, folder.resolveSymbolicLinksSync())) {
        files.addAll(
          folder
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .map((file) => file.path),
        );
      }
    }
    return files
        .map((path) => 'packages/$packageName/${_getRelativePath(path)}')
        .toList()
      ..sort();
  }

  File? findFile(String asset) {
    final prefix = 'packages/$packageName/';
    if (asset.startsWith(prefix)) {
      return findConfinedFile(directory, asset.substring(prefix.length));
    }
    if (asset.startsWith('assets/')) {
      return findConfinedFile(directory, asset);
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
