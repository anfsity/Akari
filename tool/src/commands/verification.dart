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
        id: 'backend.format',
        command: ['cargo', 'fmt', '--all', '--', '--check'],
        workingDirectory: 'backend',
      ),
      RunStep(
        id: 'backend.check',
        command: ['cargo', 'check', '--locked'],
        workingDirectory: 'backend',
      ),
      RunStep(
        id: 'backend.test',
        command: ['cargo', 'test', '--locked', '--', '--test-threads=1'],
        workingDirectory: 'backend',
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
        workingDirectory: 'backend',
      ),
      for (final theme in themes)
        RunStep(
          id: '${theme.packageName}.pub_get',
          command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
          workingDirectory: theme.directory.path,
        ),
      ...createSceneGenerationSteps(repoRoot, themes),
      RunStep(
        id: 'flutter.analyze',
        command: [
          ...getFlutterCommand(repoRoot),
          'analyze',
          'lib',
          'test',
          'tool/src',
          'tool/akari.dart',
          'tool/theme_host.dart',
          'tool/theme_session.dart',
          'tool/dbus_gateway_smoke.dart',
          if (!selectedThemeOnly) 'tool/dev_main.dart',
        ],
      ),
      RunStep(
        id: 'flutter.test',
        command: [...getFlutterCommand(repoRoot), 'test'],
      ),
      RunStep(
        id: 'scene_schema.analyze',
        command: [...getDartCommand(repoRoot), 'analyze'],
        workingDirectory: 'packages/scene_schema',
      ),
      RunStep(
        id: 'scene_schema.test',
        command: [...getDartCommand(repoRoot), 'test'],
        workingDirectory: 'packages/scene_schema',
      ),
      RunStep(
        id: 'scene_codegen.analyze',
        command: [...getDartCommand(repoRoot), 'analyze'],
        workingDirectory: 'packages/scene_codegen',
      ),
      RunStep(
        id: 'scene_codegen.test',
        command: [...getDartCommand(repoRoot), 'test'],
        workingDirectory: 'packages/scene_codegen',
      ),
      RunStep(
        id: 'scene.analyze',
        command: [...getFlutterCommand(repoRoot), 'analyze'],
        workingDirectory: 'packages/scene',
      ),
      RunStep(
        id: 'scene.test',
        command: [...getFlutterCommand(repoRoot), 'test'],
        workingDirectory: 'packages/scene',
      ),
      RunStep(
        id: 'greeter_ui.analyze',
        command: [...getFlutterCommand(repoRoot), 'analyze'],
        workingDirectory: 'packages/greeter_ui',
      ),
      RunStep(
        id: 'greeter_ui.test',
        command: [...getFlutterCommand(repoRoot), 'test'],
        workingDirectory: 'packages/greeter_ui',
      ),
      ..._getThemeVerificationSteps(repoRoot, themes),
      RunStep(
        id: 'dbus.smoke',
        command: [
          'bash',
          'scripts/debug-dbus.sh',
          ...getDartCommand(repoRoot),
          'run',
          'tool/dbus_gateway_smoke.dart',
        ],
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
    RunStep(
      id: 'theme_studio.pub_get',
      command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
      workingDirectory: 'packages/theme_studio',
    ),
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
