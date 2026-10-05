import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/build_links.dart';
import '../tool/src/command_plans.dart';
import '../tool/src/run_report.dart';
import '../tool/src/theme_project.dart';

void main() {
  late Directory repo;
  late ThemePackage theme;

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('akari-build-links-');
    theme = ThemePackage(
      packageName: 'theme_ocean',
      builderName: 'buildOceanTheme',
      directory: Directory('${repo.path}/theme'),
    );
  });

  tearDown(() => repo.delete(recursive: true));

  Future<void> createArtifacts(String mode) async {
    final artifacts = artifactPathsFor(
      'build',
      'runs/test',
      selectedTheme: theme,
      buildMode: mode,
    );
    for (final key in ['executable', 'backend_executable']) {
      final file = File('${repo.path}/${artifacts[key]}');
      await file.parent.create(recursive: true);
      await file.writeAsString(mode);
    }
    final asset = File(
      '${File('${repo.path}/${artifacts['executable']}').parent.path}/data/asset',
    );
    await asset.parent.create();
    await asset.writeAsString('asset');
  }

  test(
    'relative bundle and backend links follow the latest successful mode',
    () async {
      await createArtifacts('release');
      await updateBuildLinks(repo, theme, 'release');
      final bundle = Link('${repo.path}/build/out/ocean');
      final backend = Link('${repo.path}/build/out/backend');
      expect(await bundle.target(), startsWith('../../build/tool/hosts/'));
      expect(await File('${bundle.path}/greeter').readAsString(), 'release');
      expect(await File('${bundle.path}/data/asset').readAsString(), 'asset');
      expect(await File(backend.path).readAsString(), 'release');
      await createArtifacts('debug');
      await updateBuildLinks(repo, theme, 'debug');
      expect(await File('${bundle.path}/greeter').readAsString(), 'debug');
      expect(await File(backend.path).readAsString(), 'debug');
      expect(await bundle.target(), isNot(startsWith('/')));
    },
  );

  test(
    'missing artifacts and same-named projects do not replace links',
    () async {
      await createArtifacts('release');
      await updateBuildLinks(repo, theme, 'release');
      final link = Link('${repo.path}/build/out/ocean');
      final target = await link.target();
      await expectLater(
        updateBuildLinks(repo, theme, 'debug'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await link.target(), target);
      final other = ThemePackage(
        packageName: theme.packageName,
        builderName: theme.builderName,
        directory: Directory('${repo.path}/other'),
      );
      await expectLater(
        updateBuildLinks(repo, other, 'release'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await link.target(), target);
    },
  );

  test(
    'failed backend skips link publication even when frontend succeeds',
    () async {
      await createArtifacts('release');
      await updateBuildLinks(repo, theme, 'release');
      final link = Link('${repo.path}/build/out/ocean');
      final target = await link.target();
      final marker = File('${repo.path}/published');
      final result = await runDevCommand(
        command: 'build',
        format: RunOutputFormat.json,
        reportPath: null,
        repoRoot: repo,
        runDirectory: 'runs/failed',
        artifactPaths: const {},
        steps: [
          const RunStep(
            id: 'backend.build',
            command: ['bash', '-c', 'exit 7'],
            workingDirectory: '.',
            environment: {},
            dependencies: [],
          ),
          const RunStep(
            id: 'flutter.build_linux',
            command: ['true'],
            workingDirectory: '.',
            environment: {},
            dependencies: [],
          ),
          RunStep(
            id: 'build.links',
            command: ['touch', marker.path],
            workingDirectory: '.',
            environment: const {},
            dependencies: const ['backend.build', 'flutter.build_linux'],
          ),
        ],
      );
      expect(result, 1);
      expect(await marker.exists(), isFalse);
      expect(await link.target(), target);
      final plan = buildStepsFor(
        'build',
        repo,
        'runs/plan',
        selectedTheme: theme,
      );
      expect(plan.last.id, 'build.links');
      expect(plan.last.dependencies, ['backend.build', 'flutter.build_linux']);
      expect(
        buildStepsFor(
          'preview',
          repo,
          'runs/preview',
          selectedTheme: theme,
          preview: true,
        ).any((step) => step.id == 'build.links'),
        isFalse,
      );
    },
  );

  test('existing directories and reserved names are rejected', () async {
    await createArtifacts('release');
    await Directory('${repo.path}/build/out/ocean').create(recursive: true);
    await expectLater(
      updateBuildLinks(repo, theme, 'release'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await Directory('${repo.path}/build/out/ocean').exists(), isTrue);
    await expectLater(
      updateBuildLinks(
        repo,
        ThemePackage(
          packageName: 'theme_backend',
          builderName: 'buildBackendTheme',
          directory: theme.directory,
        ),
        'release',
      ),
      throwsFormatException,
    );
  });
}
