import 'dart:io';

import '../execution/model.dart';
import '../execution/paths.dart';
import '../sdk_commands.dart';
import '../theme/project.dart';
import '../theme/scene_generation.dart';
import 'plan.dart';

RunPlan createVerificationPlan(
  Directory repoRoot,
  String runDirectory,
  List<ThemePackage> themes, {
  required bool selectedThemeOnly,
}) {
  return RunPlan(
    command: 'verify',
    themes: themes,
    steps: [
      RunStep(
        id: 'toolchain.check',
        command: ['bash', 'scripts/check-toolchain.sh'],
      ),
      RunStep(
        id: 'rust.format',
        command: ['cargo', 'fmt', '--all', '--', '--check'],
        workingDirectory: 'crates',
      ),
      RunStep(
        id: 'rust.check',
        command: ['cargo', 'check', '--locked', '--workspace'],
        workingDirectory: 'crates',
      ),
      RunStep(
        id: 'backend.test',
        command: ['cargo', 'test', '--locked', '--', '--test-threads=1'],
        workingDirectory: 'crates/akari-backend',
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
      ),
      RunStep(
        id: 'splash.test',
        command: ['cargo', 'test', '--locked'],
        workingDirectory: 'crates/akari-splash',
      ),
      for (final theme in themes)
        RunStep(
          id: '${theme.packageName}.pub_get',
          command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
          workingDirectory: theme.directory.path,
        ),
      ...createSceneGenerationSteps(repoRoot, themes),
      RunStep(
        id: 'greeter.pub_get',
        command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
        workingDirectory: 'apps/greeter',
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
      ),
      RunStep(
        id: 'flutter.test',
        command: [...getFlutterCommand(repoRoot), 'test'],
        workingDirectory: 'apps/greeter',
      ),
      for (final packageName in [
        'scene_schema',
        'scene_codegen',
        'theme_project',
        'akari_cli',
      ])
        ..._getDartPackageVerificationSteps(repoRoot, packageName),
      for (final packageName in ['scene', 'greeter_ui', 'greeter_harness'])
        ..._getFlutterPackageVerificationSteps(
          repoRoot,
          Directory(getJoinedPath(repoRoot.path, 'packages/$packageName')),
          packageName,
        ),
      ..._getThemeVerificationSteps(repoRoot, themes),
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
        environment: {
          'AKARI_LOG_DIR': getJoinedPath(repoRoot.path, '$runDirectory/dbus'),
        },
      ),
    ],
  );
}

List<RunStep> _getThemeVerificationSteps(
  Directory repoRoot,
  List<ThemePackage> themes,
) {
  return [
    for (final packageName in [
      'greeter_components',
      'theme_sdk',
      'theme_studio',
    ])
      ..._getFlutterPackageVerificationSteps(
        repoRoot,
        Directory(getJoinedPath(repoRoot.path, 'packages/$packageName')),
        packageName,
      ),
    for (final theme in themes)
      ..._getFlutterPackageVerificationSteps(
        repoRoot,
        theme.directory,
        theme.packageName,
      ),
  ];
}

List<RunStep> _getFlutterPackageVerificationSteps(
  Directory repoRoot,
  Directory directory,
  String packageName,
) {
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
      id: '$packageName.pub_get',
      command: [...flutter, 'pub', 'get'],
      workingDirectory: directory.path,
    ),
    RunStep(
      id: '$packageName.analyze',
      command: [...flutter, 'analyze'],
      workingDirectory: directory.path,
    ),
    if (hasTests)
      RunStep(
        id: '$packageName.test',
        command: [...flutter, 'test'],
        workingDirectory: directory.path,
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
      ('pub_get', ['pub', 'get']),
      ('analyze', ['analyze']),
      ('test', ['test']),
    ])
      RunStep(
        id: '$packageName.${operation.$1}',
        command: [...dart, ...operation.$2],
        workingDirectory: 'packages/$packageName',
      ),
  ];
}
