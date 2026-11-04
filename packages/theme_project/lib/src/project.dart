import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

String getThemeBuilderName(String packageName) {
  if (!packageName.startsWith('theme_')) {
    throw const FormatException('Theme package names must start with theme_.');
  }
  final name = packageName.substring('theme_'.length);
  if (!RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$').hasMatch(name)) {
    throw FormatException(
      'Theme package $packageName must use a lowercase underscore name.',
    );
  }
  return 'build${name.split('_').map((word) => '${word[0].toUpperCase()}${word.substring(1)}').join()}Theme';
}

void validateThemeEntrypoint(
  String source,
  String builderName,
  String packageName,
) {
  if (!RegExp(r'\b' + RegExp.escape(builderName) + r'\s*\(').hasMatch(source)) {
    throw FormatException(
      '$packageName must export $builderName() from lib/theme.dart.',
    );
  }
}

List<File> findThemeSceneFiles(Directory project) {
  final lib = Directory(p.join(project.path, 'lib'));
  if (!lib.existsSync()) return [];
  final scenes =
      lib
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.scene.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final manifest = loadYaml(
    File(p.join(project.path, 'pubspec.yaml')).readAsStringSync(),
  );
  final metadata = manifest is Map ? manifest['akari'] : null;
  if (metadata == null) return scenes;
  if (metadata is! Map) {
    throw const FormatException('akari project metadata must be a map.');
  }
  final scene = metadata['scene'];
  if (scene == null) return scenes;
  if (scene is! String || p.isAbsolute(scene)) {
    throw const FormatException(
      'akari.scene must be a relative scene file path.',
    );
  }
  final primary = p.normalize(p.absolute(p.join(project.path, scene)));
  final index = scenes.indexWhere(
    (file) => p.equals(p.absolute(file.path), primary),
  );
  if (!p.isWithin(p.absolute(lib.path), primary) || index < 0) {
    throw FormatException('akari.scene is not a scene inside lib/: $scene');
  }
  scenes.insert(0, scenes.removeAt(index));
  return scenes;
}
