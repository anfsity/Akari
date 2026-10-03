import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Imports into the compiled theme package so saved scene references remain
/// portable. The manifest keeps its comments and existing asset declarations.
class StudioAssets {
  StudioAssets({required this.directory, required this.packageName});

  final Directory directory;
  final String packageName;

  String importFile(File source) {
    final name = source.uri.pathSegments.last;
    if (name.contains('..')) {
      throw const FormatException('Asset names cannot contain "..".');
    }
    final manifest = File('${directory.path}/pubspec.yaml');
    final original = manifest.readAsStringSync();
    final yaml = YamlEditor(original);
    final root = yaml.parseAt([]).value as Map;
    final flutter = root['flutter'] as Map?;
    final entries = (flutter?['assets'] as List?) ?? [];
    final assets = Directory('${directory.path}/assets')..createSync();
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    var target = File('${assets.path}/$name');
    var suffix = 2;
    while (FileSystemEntity.typeSync(target.path) !=
        FileSystemEntityType.notFound) {
      target = File('${assets.path}/$stem-${suffix++}$extension');
    }
    final relative = 'assets/${target.uri.pathSegments.last}';
    if (!entries.contains('assets/') && !entries.contains(relative)) {
      if (flutter == null) {
        yaml.update(
          ['flutter'],
          {
            'assets': [relative],
          },
        );
      } else {
        yaml.update(['flutter', 'assets'], [...entries, relative]);
      }
    }
    // Stage both writes before exposing either destination. If manifest update
    // fails, remove our new asset rather than leave an unregistered import.
    final staging = directory.createTempSync('.studio-import-');
    var copied = false;
    try {
      final stagedAsset = source.copySync('${staging.path}/asset');
      final stagedManifest = File('${staging.path}/pubspec.yaml')
        ..writeAsStringSync(yaml.toString(), flush: true);
      if (manifest.readAsStringSync() != original) {
        throw const FileSystemException(
          'Theme manifest changed during import.',
        );
      }
      stagedAsset.renameSync(target.path);
      copied = true;
      if (yaml.toString() != original) stagedManifest.renameSync(manifest.path);
    } on Object {
      if (copied) target.deleteSync();
      rethrow;
    } finally {
      staging.deleteSync(recursive: true);
    }
    return 'packages/$packageName/$relative';
  }

  List<String> getAssets() {
    final assets = Directory('${directory.path}/assets');
    if (!assets.existsSync()) return [];
    return assets.listSync(followLinks: false).whereType<File>().map((file) {
      return 'packages/$packageName/assets/${file.uri.pathSegments.last}';
    }).toList()..sort();
  }

  ImageProvider getImageProvider(String asset) {
    final prefix = 'packages/$packageName/';
    if (asset.startsWith(prefix)) {
      return FileImage(
        File('${directory.path}/${asset.substring(prefix.length)}'),
      );
    }
    if (asset.startsWith('assets/')) {
      return FileImage(File('${directory.path}/$asset'));
    }
    return AssetImage(asset);
  }
}
