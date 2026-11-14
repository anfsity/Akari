import 'dart:io';

import '../execution/model.dart';
import '../execution/paths.dart';
import '../sdk_commands.dart';
import '../theme/model.dart';
import '../theme/project.dart';
import '../theme/scene_generation.dart';
import 'plan.dart';
import 'theme.dart' show createBackendBuildStep;

RunPlan createVerificationPlan(
  Directory repoRoot,
  String runDirectory,
  List<ThemePackage> themes, {
  required bool selectedThemeOnly,
}) {
  final sceneSteps = [
    for (final theme in themes) 'scenes.generate_${theme.packageName}',
  ];
  return RunPlan(
    command: 'verify',
    themes: themes,
    steps: [
      RunStep(
        id: 'toolchain.check',
        command: ['bash', 'scripts/check-toolchain.sh'],
        dependencies: const [],
      ),
      RunStep(
        id: 'rust.format',
        command: ['cargo', 'fmt', '--all', '--', '--check'],
        workingDirectory: 'crates',
        dependencies: const [],
      ),
      RunStep(
        id: 'rust.check',
        command: ['cargo', 'check', '--locked', '--workspace'],
        workingDirectory: 'crates',
        dependencies: const ['rust.format'],
      ),
      RunStep(
        id: 'backend.test',
        command: ['cargo', 'test', '--locked', '--', '--test-threads=1'],
        workingDirectory: 'crates/akari-backend',
        dependencies: const ['rust.check'],
      ),
      RunStep(
        id: 'backend.test_mock',
        command: [
          'cargo',
          'test',
          '--locked',
          '--features',
          'mock',
          '--',
          '--test-threads=1',
        ],
        workingDirectory: 'crates/akari-backend',
        dependencies: const ['rust.check'],
      ),
      RunStep(
        id: 'splash.test',
        command: ['cargo', 'test', '--locked'],
        workingDirectory: 'crates/akari-splash',
        dependencies: const ['rust.check'],
      ),
      for (final theme in themes)
        RunStep(
          id: '${theme.packageName}.pub_get',
          command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
          workingDirectory: theme.directory.path,
          dependencies: const [],
        ),
      ...createSceneGenerationSteps(
        repoRoot,
        themes,
        dependenciesFor: (theme) => ['${theme.packageName}.pub_get'],
      ),
      RunStep(
        id: 'greeter.pub_get',
        command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
        workingDirectory: 'apps/greeter',
        dependencies: const [],
      ),
      RunStep(
        id: 'flutter.analyze',
        command: [
          ...getFlutterCommand(repoRoot),
          'analyze',
          'lib/app',
          'lib/infrastructure',
          'test',
          if (!selectedThemeOnly) 'lib/main.dart',
        ],
        workingDirectory: 'apps/greeter',
        dependencies: ['greeter.pub_get', ...sceneSteps],
      ),
      RunStep(
        id: 'flutter.test',
        command: [...getFlutterCommand(repoRoot), 'test'],
        workingDirectory: 'apps/greeter',
        dependencies: ['greeter.pub_get', ...sceneSteps],
      ),
      for (final packageName in [
        'scene_schema',
        'scene_codegen',
        'theme_project',
        'akari_cli',
      ])
        ..._getDartPackageVerificationSteps(repoRoot, packageName),
      for (final packageName in [
        'scene',
        'greeter_ui',
        'greeter_harness',
        'greeter_components',
        'theme_sdk',
        'theme_studio',
      ]) ...[
        RunStep(
          id: '$packageName.pub_get',
          command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
          workingDirectory: 'packages/$packageName',
          dependencies: const [],
        ),
        ..._getFlutterPackageVerificationSteps(
          repoRoot,
          Directory(getJoinedPath(repoRoot.path, 'packages/$packageName')),
          packageName,
          dependencies: ['$packageName.pub_get'],
        ),
      ],
      for (final theme in themes)
        ..._getFlutterPackageVerificationSteps(
          repoRoot,
          theme.directory,
          theme.packageName,
          dependencies: ['scenes.generate_${theme.packageName}'],
        ),
      createBackendBuildStep(BackendMode.mock, BuildMode.debug, null),
      RunStep(
        id: 'dbus.smoke',
        command: [
          'bash',
          '${repoRoot.path}/scripts/debug-dbus.sh',
          ...getFlutterCommand(repoRoot),
          'test',
          'test/dbus_gateway_smoke.dart',
        ],
        workingDirectory: 'apps/greeter',
        dependencies: ['backend.build', 'greeter.pub_get', ...sceneSteps],
        environment: {
          'AKARI_BACKEND_BIN': getAbsolutePath(
            repoRoot,
            getBackendExecutablePath(BackendMode.mock, BuildMode.debug),
          ),
          'AKARI_LOG_DIR': getJoinedPath(repoRoot.path, '$runDirectory/dbus'),
        },
      ),
    ],
  );
}

List<RunStep> _getFlutterPackageVerificationSteps(
  Directory repoRoot,
  Directory directory,
  String packageName, {
  required List<String> dependencies,
}) {
  final testDirectory = Directory(getJoinedPath(directory.path, 'test'));
  final hasTests =
      testDirectory.existsSync() &&
      testDirectory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .any((file) => file.path.endsWith('_test.dart'));
  final flutter = getFlutterCommand(repoRoot);

  return [
    RunStep(
      id: '$packageName.analyze',
      command: [...flutter, 'analyze'],
      workingDirectory: directory.path,
      dependencies: dependencies,
    ),
    if (hasTests)
      RunStep(
        id: '$packageName.test',
        command: [...flutter, 'test'],
        workingDirectory: directory.path,
        dependencies: dependencies,
      ),
  ];
}

List<RunStep> _getDartPackageVerificationSteps(
  Directory repoRoot,
  String packageName,
) {
  final dart = getDartCommand(repoRoot);
  return [
    for (final operation in [
      ('pub_get', ['pub', 'get'], const <String>[]),
      ('analyze', ['analyze'], ['$packageName.pub_get']),
      ('test', ['test'], ['$packageName.pub_get']),
    ])
      RunStep(
        id: '$packageName.${operation.$1}',
        command: [...dart, ...operation.$2],
        workingDirectory: 'packages/$packageName',
        dependencies: operation.$3,
      ),
  ];
}
