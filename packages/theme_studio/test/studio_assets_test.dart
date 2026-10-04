import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_studio/src/studio_assets.dart';
import 'package:yaml_edit/yaml_edit.dart';

void main() {
  late Directory directory;
  late File manifest;
  late StudioAssets assets;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('studio-assets-');
    manifest = File('${directory.path}/pubspec.yaml')
      ..writeAsStringSync('# keep this comment\nname: test\n');
    assets = StudioAssets(directory: directory, packageName: 'test');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'finds a scene theme by its manifest through nested paths and symlinks',
    () {
      final theme = Directory('${directory.path}/different-folder')
        ..createSync();
      File('${theme.path}/pubspec.yaml')
          .writeAsStringSync('name: theme_ocean\n');
      final scene = File('${theme.path}/lib/scenes/ocean.scene.json');
      scene.parent.createSync(recursive: true);
      scene.writeAsStringSync('{}');
      final link = Link('${directory.path}/linked.json')
        ..createSync(scene.path);
      for (final file in [scene, File(link.path)]) {
        final found = StudioAssets.findForScene(file)!;
        expect(found.directory.path, theme.resolveSymbolicLinksSync());
        expect(found.packageName, 'theme_ocean');
      }
    },
  );

  test('standalone scenes stop at a non-theme package boundary', () {
    manifest.writeAsStringSync('name: theme_parent\n');
    final standalone = File('${directory.path}/nested/lib/scene.json');
    standalone.parent.createSync(recursive: true);
    File('${directory.path}/nested/pubspec.yaml')
        .writeAsStringSync('name: standalone\n');
    standalone.writeAsStringSync('{}');
    expect(StudioAssets.findForScene(standalone), isNull);
    manifest.deleteSync();
    final external = File('${directory.path}/external.json')
      ..writeAsStringSync('{}');
    expect(StudioAssets.findForScene(external), isNull);
  });

  test('imports portable assets, registers manifest and avoids overwrites', () {
    final source = File('${directory.path}/picture.png')
      ..writeAsBytesSync([1, 2]);
    final first = assets.importFile(source);
    final second = assets.importFile(source);
    expect(first, 'packages/test/assets/picture.png');
    expect(second, 'packages/test/assets/picture-2.png');
    expect(assets.getAssets(), [second, first]);
    expect(File('${directory.path}/assets/picture.png').readAsBytesSync(), [
      1,
      2,
    ]);
    final content = manifest.readAsStringSync();
    expect(content, startsWith('# keep this comment'));
    expect(YamlEditor(content).parseAt(['flutter', 'assets']).value, [
      'assets/picture.png',
      'assets/picture-2.png',
    ]);
    expect(
      (assets.getImageProvider(first) as FileImage).file.path,
      '${directory.path}/assets/picture.png',
    );
    expect(
      assets.getImageProvider('packages/other/assets/picture.png'),
      isA<AssetImage>(),
    );
  });

  test('directory asset registration is preserved and failed copies leave no entry', () {
    const sourceManifest = 'name: test\nflutter:\n  assets:\n    - assets/\n';
    manifest.writeAsStringSync(sourceManifest);
    final source = File('${directory.path}/font.ttf')
      ..writeAsStringSync('font');
    assets.importFile(source);
    expect(manifest.readAsStringSync(), sourceManifest);
    expect(
      () => assets.importFile(File('${directory.path}/missing.png')),
      throwsA(isA<FileSystemException>()),
    );
    expect(assets.getAssets(), ['packages/test/assets/font.ttf']);
    expect(
      directory.listSync().whereType<Directory>().where(
        (entry) => entry.path.contains('.studio-import-'),
      ),
      isEmpty,
    );
  });
}
