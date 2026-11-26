import 'dart:io';

import '../execution/model.dart';
import '../execution/paths.dart';
import '../sdk_commands.dart';
import '../theme/model.dart';
import '../theme/project.dart';
import '../theme/scene_generation.dart';
import 'plan.dart';
import 'theme.dart' show createBackendBuildStep;

const _standaloneWorkflowSuites = [
  'greetd_test_workflow_test.py',
  'greetd_screenshot_test.py',
  'display_profile_test.py',
  'display_layout_test.py',
  'sway_session_test.py',
  'login_workflow_test.py',
  'gaze_pam_test.py',
  'splash_workflow_test.py',
];

RunPlan createVerificationPlan(
  Directory repoRoot,
  String runDirectory,
  List<ThemePackage> themes, {
  required bool selectedThemeOnly,
}) {
  final generationThemes = [...themes];
  final defaultThemeDirectory = Directory(
    getJoinedPath(repoRoot.path, 'themes/default'),
  );
  final defaultSceneOutput = File(
    getJoinedPath(repoRoot.path, 'themes/default/lib/default.scene.g.dart'),
  );
  if (selectedThemeOnly &&
      !generationThemes.any((t) => t.packageName == 'theme_default') &&
      defaultThemeDirectory.existsSync() &&
      !defaultSceneOutput.existsSync()) {
    generationThemes.add(getThemePackage(defaultThemeDirectory));
  }
  final sceneSteps = [
    for (final theme in generationThemes)
      'scenes.generate_${theme.packageName}',
  ];
  final defaultSceneStep = sceneSteps.contains('scenes.generate_theme_default')
      ? const ['scenes.generate_theme_default']
      : const <String>[];
  final externalThemes = [
    for (final theme in generationThemes)
      if (!isWorkspaceMember(repoRoot, theme.directory)) theme,
  ];
  final externalPubGetIds = {
    for (final theme in externalThemes)
      theme.packageName: '${theme.packageName}.pub_get',
  };
  final workflowSuites = [
    for (final suite in _standaloneWorkflowSuites)
      if (File(getJoinedPath(repoRoot.path, 'test/workflows/$suite'))
          .existsSync())
        suite,
  ];

  return RunPlan(
    command: 'verify',
    themes: themes,
    steps: [
      const RunStep(
        id: 'toolchain.check',
        command: ['bash', 'scripts/check-toolchain.sh'],
        dependencies: [],
      ),
      const RunStep(
        id: 'rust.format',
        command: ['cargo', 'fmt', '--all', '--', '--check'],
        workingDirectory: 'crates',
        dependencies: [],
      ),
      const RunStep(
        id: 'rust.check',
        command: ['cargo', 'check', '--locked', '--workspace'],
        workingDirectory: 'crates',
        dependencies: ['rust.format'],
      ),
      // Serialize Cargo steps that share crates/target: Cargo releases its
      // build lock before running test binaries, so concurrent feature builds
      // would overwrite crates/target/debug/backend mid-test while blocking
      // runner concurrency slots on crates/target/.cargo-lock.
      const RunStep(
        id: 'rust.clippy',
        command: [
          'cargo',
          'clippy',
          '--locked',
          '--workspace',
          '--all-targets',
          '--',
          '-D',
          'warnings',
        ],
        workingDirectory: 'crates',
        dependencies: ['rust.check'],
      ),
      const RunStep(
        id: 'rust.clippy_mock',
        command: [
          'cargo',
          'clippy',
          '--locked',
          '--workspace',
          '--all-targets',
          '--features',
          'mock',
          '--',
          '-D',
          'warnings',
        ],
        workingDirectory: 'crates',
        dependencies: ['rust.clippy'],
      ),
      const RunStep(
        id: 'backend.test',
        command: ['cargo', 'test', '--locked'],
        workingDirectory: 'crates/akari-backend',
        dependencies: ['rust.clippy_mock'],
      ),
      const RunStep(
        id: 'backend.test_mock',
        command: ['cargo', 'test', '--locked', '--features', 'mock'],
        workingDirectory: 'crates/akari-backend',
        dependencies: ['backend.test'],
      ),
      const RunStep(
        id: 'splash.test',
        command: ['cargo', 'test', '--locked'],
        workingDirectory: 'crates/akari-splash',
        dependencies: ['backend.test_mock'],
      ),
      if (workflowSuites.isNotEmpty)
        RunStep(
          id: 'workflows.test',
          command: ['python3', '-m', 'unittest', ...workflowSuites],
          workingDirectory: 'test/workflows',
          dependencies: const [],
        ),
      RunStep(
        id: 'workspace.pub_get',
        command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
        workingDirectory: '.',
        dependencies: const ['toolchain.check'],
      ),
      for (final theme in externalThemes)
        RunStep(
          id: externalPubGetIds[theme.packageName]!,
          command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
          workingDirectory: theme.directory.path,
          dependencies: const ['workspace.pub_get'],
        ),
      ...createSceneGenerationSteps(
        repoRoot,
        generationThemes,
        dependenciesFor: (theme) => [
          externalPubGetIds[theme.packageName] ?? 'workspace.pub_get',
        ],
      ),
      RunStep(
        id: 'flutter.analyze',
        command: [
          ...getFlutterCommand(repoRoot),
          'analyze',
          '--no-pub',
          'lib/app',
          'lib/infrastructure',
          'test',
          if (!selectedThemeOnly) 'lib/main.dart',
        ],
        workingDirectory: 'apps/greeter',
        dependencies: ['workspace.pub_get', ...sceneSteps],
      ),
      RunStep(
        id: 'flutter.test',
        command: [...getFlutterCommand(repoRoot), 'test', '--no-pub'],
        workingDirectory: 'apps/greeter',
        dependencies: ['workspace.pub_get', ...sceneSteps],
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
      ])
        ..._getFlutterPackageVerificationSteps(
          repoRoot,
          Directory(getJoinedPath(repoRoot.path, 'packages/$packageName')),
          packageName,
          dependencies: [
            'workspace.pub_get',
            if (packageName == 'greeter_ui' || packageName == 'greeter_harness')
              ...defaultSceneStep,
          ],
        ),
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
          '--no-pub',
          'test/dbus_gateway_smoke.dart',
        ],
        workingDirectory: 'apps/greeter',
        dependencies: ['backend.build', 'workspace.pub_get', ...sceneSteps],
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
      command: [...flutter, 'analyze', '--no-pub'],
      workingDirectory: directory.path,
      dependencies: dependencies,
    ),
    if (hasTests)
      RunStep(
        id: '$packageName.test',
        command: [...flutter, 'test', '--no-pub'],
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
      ('analyze', ['analyze']),
      ('test', ['test']),
    ])
      RunStep(
        id: '$packageName.${operation.$1}',
        command: [...dart, ...operation.$2],
        workingDirectory: 'packages/$packageName',
        dependencies: const ['workspace.pub_get'],
      ),
  ];
}
