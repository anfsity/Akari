import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scene_codegen/scene_codegen.dart';
import 'package:scene_schema/scene_schema.dart';
import 'package:test/test.dart';
import 'package:theme_project/theme_project.dart';
import 'package:yaml/yaml.dart';

const _document = SceneDocument(
  id: '123 custom',
  version: currentSceneVersion,
  canvas: SceneCanvas(),
  background: SceneBackground(
    kind: SceneBackgroundKind.image,
    asset: 'packages/external/assets/wallpaper.png',
  ),
  themeProperties: {
    'layout': 'centered',
    'palette': 'rose',
    'material': 'frosted',
    'motion': 'none',
    'private': 'keep',
  },
  nodes: [
    SceneNode(
      id: 'caption',
      componentId: 'label',
      rect: SceneRect(x: 0.3, y: 0.3, width: 0.4, height: 0.1),
      properties: {
        'text': 'Edited greeting',
        'image': 'packages/theme_original/assets/sticker.png',
      },
    ),
  ],
);

void main() {
  late Directory root;
  late Directory source;
  late Directory target;
  late File wallpaper;

  Future<void> write(String relative, String content) async {
    final file = File(p.join(source.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('theme-synthesis-');
    source = Directory(p.join(root.path, 'presets', 'original'));
    target = Directory(p.join(root.path, 'works', 'neon'));
    wallpaper = File(p.join(root.path, 'external', 'wallpaper.png'));
    await wallpaper.parent.create(recursive: true);
    await wallpaper.writeAsBytes([1, 2, 3, 4]);
    await write('pubspec.yaml', '''
# Keep author metadata.
name: theme_original
environment:
  sdk: ^3.13.2
dependencies:
  theme_sdk:
    path: ../../sdk/theme_sdk
dev_dependencies:
  scene_codegen:
    path: ../../sdk/scene_codegen
dependency_overrides:
  scene:
    path: ../../sdk/scene
flutter:
  assets:
    - assets/
    - wallpapers/
  fonts:
    - family: StudioFont
      fonts:
        - asset: assets/fonts/font.otf
  shaders:
    - lib/shaders/paint.frag
  licenses:
    - assets/fonts/OFL.txt
''');
    await write('lib/theme.dart', '''
import 'package:theme_original/labels.dart';
const font = 'packages/theme_original/StudioFont';
ThemeDefinition buildOriginalTheme({Color? seed, SceneDocument? document}) => throw UnimplementedError();
''');
    await write(
      'lib/labels.dart',
      "const image = 'packages/theme_original/assets/sticker.png';",
    );
    await write(
      'lib/aaa.scene.json',
      encodeSceneDocument(
        _document.copyWith(
          id: 'source',
          background: const SceneBackground(kind: SceneBackgroundKind.solid),
        ),
      ),
    );
    await write('lib/aaa.scene.g.dart', 'obsolete generated code');
    await write('lib/shaders/paint.frag', 'shader source');
    await write('assets/fonts/font.otf', 'font bytes');
    await write('assets/fonts/OFL.txt', 'font license');
    await write('assets/sticker.png', 'sticker bytes');
    await write('wallpapers/preset.png', 'declared custom resource');
    await write('README.md', 'Author instructions');
    await write('LICENSE', 'Author license');
    await write('lib/build/stale', 'build cache');
    await write('.env', 'unrelated local data');
  });
  tearDown(() => root.delete(recursive: true));

  test('shader sources and textures are rewritten and registered for production compilation', () async {
    final shader = File('${root.path}/external/effect.frag')
      ..writeAsStringSync('void main() {}');
    final result = await createThemeProject(
      source: source,
      destination: target,
      packageName: 'theme_neon',
      document: _document.copyWith(
        background: const SceneBackground(
          kind: SceneBackgroundKind.custom,
          shader: SceneShader(
            asset: 'packages/external/effect.frag',
            uniforms: [
              SceneShaderUniform(name: 'time', source: SceneUniformSource.time),
            ],
            textures: [
              SceneShaderTexture(
                name: 'image',
                asset: 'packages/external/assets/wallpaper.png',
              ),
            ],
          ),
        ),
      ),
      assetFiles: {
        'packages/external/effect.frag': shader,
        'packages/external/assets/wallpaper.png': wallpaper,
      },
    );
    final definition = result.document.background.shader!;
    expect(definition.asset, 'packages/theme_neon/assets/composed/effect.frag');
    expect(
      definition.textures.single.asset,
      'packages/theme_neon/assets/composed/wallpaper.png',
    );
    final manifest = loadYaml(
      await File('${target.path}/pubspec.yaml').readAsString(),
    ) as Map;
    expect(
      (manifest['flutter'] as Map)['shaders'],
      contains('assets/composed/effect.frag'),
    );
    expect(
      await File('${target.path}/assets/composed/effect.frag').readAsString(),
      'void main() {}',
    );
  });

  test(
    'copies typed SVG assets and preserves their tint in an independent theme',
    () async {
      final icon = File(p.join(root.path, 'external', 'icon.svg'));
      await icon.writeAsString('<svg xmlns="http://www.w3.org/2000/svg"/>');
      final font = File(p.join(root.path, 'external', 'type.otf'));
      await font.writeAsString('font bytes');
      final document = _document.copyWith(
        styleTokens: {
          'type': const SceneStyle(
            fontAsset: 'packages/external/assets/type.otf',
            fontWeight: 700,
          ),
        },
        nodes: [
          _document.nodes.single.copyWith(
            asset: const SceneAsset(
              path: 'packages/external/assets/icon.svg',
              kind: SceneAssetKind.svg,
              tint: 0xff123456,
            ),
          ),
        ],
      );
      final result = await createThemeProject(
        source: source,
        destination: target,
        packageName: 'theme_icons',
        document: document,
        assetFiles: {
          document.background.asset!: wallpaper,
          'packages/external/assets/icon.svg': icon,
          'packages/external/assets/type.otf': font,
        },
      );
      expect(
        result.document.nodes.single.asset!.path,
        'packages/theme_icons/assets/composed/icon.svg',
      );
      expect(result.document.nodes.single.asset!.tint, 0xff123456);
      expect(
        result.document.styleTokens['type']!.fontAsset,
        'packages/theme_icons/assets/composed/type.otf',
      );
      expect(
        await File(p.join(target.path, 'assets/composed/type.otf'))
            .readAsString(),
        'font bytes',
      );
      expect(
        await File(p.join(target.path, 'assets/composed/icon.svg'))
            .readAsString(),
        await icon.readAsString(),
      );
    },
  );

  test('synthesizes an independent package with edited scene, fonts, assets and entrypoint', () async {
    final sourceManifest = await File(p.join(source.path, 'pubspec.yaml'))
        .readAsString();
    final result = await createThemeProject(
      source: source,
      destination: target,
      packageName: 'theme_neon',
      document: _document,
      assetFiles: {_document.background.asset!: wallpaper},
    );
    expect(result.packageName, 'theme_neon');
    expect(
      await File(p.join(source.path, 'pubspec.yaml')).readAsString(),
      sourceManifest,
    );
    final manifest = loadYaml(
      await File(p.join(target.path, 'pubspec.yaml')).readAsString(),
    ) as Map;
    expect(manifest['name'], 'theme_neon');
    expect((manifest['akari'] as Map)['scene'], 'lib/composition.scene.json');
    for (final (section, name, relative) in [
      ('dependencies', 'theme_sdk', 'sdk/theme_sdk'),
      ('dev_dependencies', 'scene_codegen', 'sdk/scene_codegen'),
      ('dependency_overrides', 'scene', 'sdk/scene'),
    ]) {
      final path = ((manifest[section] as Map)[name] as Map)['path'] as String;
      expect(
        p.normalize(p.join(target.path, path)),
        p.join(root.path, relative),
      );
    }
    final flutter = manifest['flutter'] as Map;
    expect(flutter['fonts'], isNotEmpty);
    expect(flutter['assets'], contains('assets/composed/wallpaper.png'));
    expect(
      await File(p.join(target.path, 'assets/fonts/font.otf')).readAsString(),
      'font bytes',
    );
    expect(
      await File(p.join(target.path, 'assets/fonts/OFL.txt')).readAsString(),
      'font license',
    );
    expect(
      await File(p.join(target.path, 'wallpapers/preset.png')).readAsString(),
      'declared custom resource',
    );
    expect(
      await File(p.join(target.path, 'lib/shaders/paint.frag')).readAsString(),
      'shader source',
    );
    expect(
      await File(p.join(target.path, 'lib/aaa.scene.g.dart')).readAsString(),
      isNot(contains('obsolete')),
    );
    expect(
      await File(p.join(target.path, 'lib/build/stale')).exists(),
      isFalse,
    );
    expect(await File(p.join(target.path, '.env')).exists(), isFalse);
    final entrypoint = await File(p.join(target.path, 'lib/theme.dart'))
        .readAsString();
    expect(entrypoint, contains('buildNeonTheme'));
    expect(
      entrypoint,
      contains(
        'document ?? composition.${getSceneDocumentVariableName(_document.id)}',
      ),
    );
    expect(entrypoint, contains('preset.buildOriginalTheme'));
    expect(entrypoint, isNot(contains('package:theme_original/')));
    final localSource = await File(p.join(target.path, 'lib/source_theme.dart'))
        .readAsString();
    expect(localSource, contains('package:theme_neon/labels.dart'));
    expect(localSource, contains('packages/theme_neon/StudioFont'));
    final document = decodeSceneDocument(
      await File(result.scenePath).readAsString(),
    );
    expect(document.id, _document.id);
    expect(document.themeProperties, _document.themeProperties);
    expect(document.nodes.single.properties['text'], 'Edited greeting');
    expect(
      document.nodes.single.properties['image'],
      'packages/theme_neon/assets/sticker.png',
    );
    expect(
      document.background.asset,
      'packages/theme_neon/assets/composed/wallpaper.png',
    );
    expect(findThemeSceneFiles(target).first.path, result.scenePath);
    expect(
      await File(p.join(target.path, 'README.md')).readAsString(),
      contains('Author instructions'),
    );
    await source.delete(recursive: true);
    await wallpaper.delete();
    expect(
      await File(p.join(target.path, 'assets/composed/wallpaper.png'))
          .readAsBytes(),
      [1, 2, 3, 4],
    );
    expect(
      await File(p.join(target.path, 'LICENSE')).readAsString(),
      'Author license',
    );
    // Execute the generated scene without Flutter to prove its getter and
    // serialized choices agree, including scene IDs that start with a digit.
    final generated = await File(
      p.join(target.path, 'lib/composition.scene.g.dart'),
    ).readAsString();
    final script = File(p.join(root.path, 'generated.dart'));
    await script.writeAsString(
      "${generated.replaceAll('package:scene/scene.dart', 'package:scene_schema/scene_schema.dart')}\nvoid main() { print(encodeSceneDocument(${getSceneDocumentVariableName(_document.id)})); }\n",
    );
    final run = await Process.run(Platform.resolvedExecutable, [
      '--packages=${File('.dart_tool/package_config.json').absolute.path}',
      script.path,
    ]);
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect(
      jsonDecode(run.stdout as String),
      jsonDecode(encodeSceneDocument(document)),
    );
  });

  test(
    'rebases external Dart directives while preserving local code',
    () async {
      final shared = Directory(p.join(root.path, "shared 'sdk\$"));
      await shared.create();
      for (final name in ['stub', 'native', 'exported']) {
        await File(p.join(shared.path, '$name.dart'))
            .writeAsString("const $name = '$name';");
      }
      String getSourceUri(String name) => Uri.file(
        p.relative(
          p.join(shared.path, '$name.dart'),
          from: p.join(source.path, 'perf'),
        ),
      ).toString();
      await write('perf/local.dart', "const local = 'local';");
      await write('perf/run.dart', '''
import 'dart:io';
import 'local.dart';
import ${encodeDartString(getSourceUri('stub'))}
  if (dart.library.io) ${encodeDartString(getSourceUri('native'))};
export ${encodeDartString(getSourceUri('exported'))};
// import '../unrelated/comment.dart';
const example = "import '../unrelated/example.dart';";
void main() { stdout.write('\$local:\$native'); }
''');
      await createThemeProject(
        source: source,
        destination: target,
        packageName: 'theme_neon',
        document: _document,
      );
      final script = File(p.join(target.path, 'perf/run.dart'));
      final copied = await script.readAsString();
      expect(copied, contains("import 'local.dart'"));
      expect(copied, contains("// import '../unrelated/comment.dart';"));
      expect(
        copied,
        contains("const example = \"import '../unrelated/example.dart';\";"),
      );
      await source.delete(recursive: true);
      final run = await Process.run(Platform.resolvedExecutable, [script.path]);
      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
      expect(run.stdout, 'local:native');
    },
  );

  test(
    'absolute SDK paths and unregistered referenced resources remain usable',
    () async {
      final manifest = File(p.join(source.path, 'pubspec.yaml'));
      await manifest.writeAsString(
        (await manifest.readAsString()).replaceFirst(
          '../../sdk/theme_sdk',
          p.join(root.path, 'sdk/theme_sdk'),
        ),
      );
      await write('private_images/current.png', 'selected wallpaper');
      final resource = File(p.join(source.path, 'private_images/current.png'));
      final result = await createThemeProject(
        source: source,
        destination: target,
        packageName: 'theme_copy',
        document: _document,
        assetFiles: {_document.background.asset!: resource},
      );
      final yaml = loadYaml(
        await File(p.join(target.path, 'pubspec.yaml')).readAsString(),
      ) as Map;
      final sdkPath =
          ((yaml['dependencies'] as Map)['theme_sdk'] as Map)['path'] as String;
      expect(
        p.normalize(p.join(target.path, sdkPath)),
        p.join(root.path, 'sdk/theme_sdk'),
      );
      expect(
        result.document.background.asset,
        'packages/theme_copy/assets/composed/current.png',
      );
      expect(
        (yaml['flutter'] as Map)['assets'],
        contains('assets/composed/current.png'),
      );
      expect(
        await File(p.join(target.path, 'assets/composed/current.png'))
            .readAsString(),
        'selected wallpaper',
      );
    },
  );

  test(
    'preserves local library collisions and deduplicates imported filenames',
    () async {
      await write('lib/source_theme.dart', 'const original = true;');
      final second = File(p.join(root.path, 'other', 'wallpaper.png'));
      await second.parent.create();
      await second.writeAsBytes([5, 6]);
      final document = _document.copyWith(
        nodes: [
          _document.nodes.single.copyWith(
            properties: {'image': 'packages/other/wallpaper.png'},
          ),
        ],
      );
      final result = await createThemeProject(
        source: source,
        destination: target,
        packageName: 'theme_copy',
        document: document,
        assetFiles: {
          document.background.asset!: wallpaper,
          'packages/other/wallpaper.png': second,
        },
      );
      expect(
        await File(p.join(target.path, 'lib/source_theme.dart')).readAsString(),
        'const original = true;',
      );
      expect(
        await File(p.join(target.path, 'lib/theme.dart')).readAsString(),
        contains("import 'source_theme_2.dart' as preset"),
      );
      expect(
        result.document.nodes.single.properties['image'],
        'packages/theme_copy/assets/composed/wallpaper-2.png',
      );
      expect(
        await File(p.join(target.path, 'assets/composed/wallpaper-2.png'))
            .readAsBytes(),
        [5, 6],
      );
    },
  );

  test(
    'refuses existing targets, source nesting and symlink aliases',
    () async {
      await target.create(recursive: true);
      await File(p.join(target.path, 'marker')).writeAsString('untouched');
      Future<SynthesizedTheme> create(Directory destination) =>
          createThemeProject(
            source: source,
            destination: destination,
            packageName: 'theme_copy',
            document: _document,
          );
      await expectLater(create(target), throwsA(isA<FileSystemException>()));
      expect(
        await File(p.join(target.path, 'marker')).readAsString(),
        'untouched',
      );
      await expectLater(create(source), throwsA(isA<FileSystemException>()));
      await expectLater(
        create(Directory(p.join(source.path, 'nested', 'theme'))),
        throwsA(isA<FileSystemException>()),
      );
      expect(await Directory(p.join(source.path, 'nested')).exists(), isFalse);
      final alias = Link(p.join(root.path, 'alias'));
      await alias.create(source.path);
      await expectLater(
        create(Directory(p.join(alias.path, 'nested'))),
        throwsA(isA<FileSystemException>()),
      );
      expect(await Directory(p.join(source.path, 'nested')).exists(), isFalse);
    },
  );

  test(
    'failed generation and cyclic source links publish no partial project',
    () async {
      await write('lib/invalid.scene.json', 'invalid scene');
      await expectLater(
        createThemeProject(
          source: source,
          destination: target,
          packageName: 'theme_copy',
          document: _document,
        ),
        throwsFormatException,
      );
      expect(await target.exists(), isFalse);
      expect(
        await target.parent
            .list()
            .where(
              (entry) => p.basename(entry.path).startsWith('.akari-theme-'),
            )
            .toList(),
        isEmpty,
      );
      await File(p.join(source.path, 'lib/invalid.scene.json')).delete();
      await Link(p.join(source.path, 'lib/loop'))
          .create(p.join(source.path, 'lib'));
      await expectLater(
        createThemeProject(
          source: source,
          destination: target,
          packageName: 'theme_copy',
          document: _document,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await target.exists(), isFalse);
    },
  );

  test(
    'naming and explicit primary-scene metadata share one contract',
    () async {
      expect(
        getThemeBuilderName('theme_neon_cyberpunk'),
        'buildNeonCyberpunkTheme',
      );
      for (final name in [
        'neon',
        'theme_',
        'theme_Upper',
        'theme_bad-name',
        'theme_bad__name',
      ]) {
        expect(() => getThemeBuilderName(name), throwsFormatException);
      }
      expect(
        () => validateThemeEntrypoint(
          'void unrelated() {}',
          'buildOriginalTheme',
          'theme_original',
        ),
        throwsFormatException,
      );
      final manifest = File(p.join(source.path, 'pubspec.yaml'));
      final original = await manifest.readAsString();
      for (final scene in [
        '../outside.scene.json',
        '/tmp/outside.scene.json',
        'lib/missing.scene.json',
      ]) {
        await manifest.writeAsString('$original\nakari:\n  scene: $scene\n');
        expect(() => findThemeSceneFiles(source), throwsFormatException);
      }
    },
  );
}
