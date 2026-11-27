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
  'sway_session_test.py',
  'splash_workflow_test.py',
  'gaze_pam_test.py',
  'login_workflow_test.py',
  'display_profile_test.py',
  'greetd_screenshot_test.py',
  'display_layout_test.py',
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
    generationThemes.add(loadThemePackage(defaultThemeDirectory));
  }
  final sceneSteps = [
    for (final theme in generationThemes)
      'scenes.generate_${theme.packageName}',
  ];
  final defaultSceneStep = sceneSteps.contains('scenes.generate_theme_default')
      ? const ['scenes.generate_theme_default']
      : const <String>[];
  final workspaceThemes = [
    for (final theme in themes)
      if (isWorkspaceMember(repoRoot, theme.directory)) theme,
  ];
  final externalThemes = [
    for (final theme in themes)
      if (!isWorkspaceMember(repoRoot, theme.directory)) theme,
  ];
  final externalGenerationThemes = [
    for (final theme in generationThemes)
      if (!isWorkspaceMember(repoRoot, theme.directory)) theme,
  ];
  final externalPubGetIds = {
    for (final theme in externalGenerationThemes)
      theme.packageName: '${theme.packageName}.pub_get',
  };
  final workspaceSceneSteps = [
    for (final theme in generationThemes)
      if (isWorkspaceMember(repoRoot, theme.directory))
        'scenes.generate_${theme.packageName}',
  ];
  final workflowSuites = [
    for (final suite in _standaloneWorkflowSuites)
      if (File(getJoinedPath(repoRoot.path, 'test/workflows/$suite'))
          .existsSync())
        suite,
  ];
  final processors = Platform.numberOfProcessors;
  final outerConcurrency = processors.clamp(2, 8);
  final packageTestJobs = (processors ~/ outerConcurrency).clamp(1, 2);
  final heavyTestJobs = (processors ~/ 2).clamp(2, 4);
  final flutter = getFlutterCommand(repoRoot);

  RunStep? createFlutterPackageTest(
    String packageName, {
    required List<String> dependencies,
    int? concurrency,
  }) => _createFlutterTestStep(
    repoRoot,
    Directory(getJoinedPath(repoRoot.path, 'packages/$packageName')),
    packageName,
    dependencies: dependencies,
    concurrency: concurrency ?? packageTestJobs,
  );

  return RunPlan(
    command: 'verify',
    themes: themes,
    steps: [
      const RunStep(
        id: 'toolchain.check',
        command: ['bash', 'scripts/check-toolchain.sh'],
        dependencies: [],
      ),
      for (final suite in workflowSuites)
        RunStep(
          id: 'workflows.${suite.replaceFirst('_test.py', '')}',
          command: ['python3', '-m', 'unittest', suite],
          workingDirectory: 'test/workflows',
          dependencies: const [],
        ),
      const RunStep(
        id: 'rust.format',
        command: ['cargo', 'fmt', '--all', '--', '--check'],
        workingDirectory: 'crates',
        dependencies: [],
      ),
      createBackendBuildStep(BackendMode.mock, BuildMode.debug, null),
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
        dependencies: ['rust.format'],
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
      RunStep(
        id: 'workspace.pub_get',
        command: [...flutter, 'pub', 'get'],
        workingDirectory: '.',
        dependencies: const ['toolchain.check'],
      ),
      for (final theme in externalGenerationThemes)
        RunStep(
          id: externalPubGetIds[theme.packageName]!,
          command: [...flutter, 'pub', 'get'],
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
      ?createFlutterPackageTest(
        'theme_studio',
        dependencies: const ['workspace.pub_get'],
        concurrency: heavyTestJobs,
      ),
      _createDartTestStep(repoRoot, 'akari_cli', concurrency: packageTestJobs),
      RunStep(
        id: 'workspace.analyze',
        command: [
          ...flutter,
          'analyze',
          '--no-pub',
          'apps/greeter/lib/app',
          'apps/greeter/lib/infrastructure',
          'apps/greeter/test',
          if (!selectedThemeOnly) 'apps/greeter/lib/main.dart',
          'packages',
          for (final theme in workspaceThemes)
            getRelativePath(repoRoot, theme.directory.path),
        ],
        workingDirectory: '.',
        dependencies: ['workspace.pub_get', ...workspaceSceneSteps],
      ),
      for (final theme in workspaceThemes)
        ?_createFlutterTestStep(
          repoRoot,
          theme.directory,
          theme.packageName,
          dependencies: ['scenes.generate_${theme.packageName}'],
          concurrency: packageTestJobs,
        ),
      RunStep(
        id: 'flutter.test',
        command: [
          ...flutter,
          'test',
          '--no-pub',
          '--concurrency=$packageTestJobs',
        ],
        workingDirectory: 'apps/greeter',
        dependencies: ['workspace.pub_get', ...sceneSteps],
      ),
      for (final packageName in [
        'greeter_ui',
        'greeter_harness',
        'scene',
        'greeter_components',
        'theme_sdk',
      ])
        ?createFlutterPackageTest(
          packageName,
          dependencies: [
            'workspace.pub_get',
            if (packageName == 'greeter_ui' || packageName == 'greeter_harness')
              ...defaultSceneStep,
          ],
        ),
      for (final packageName in [
        'theme_project',
        'scene_codegen',
        'scene_schema',
      ])
        _createDartTestStep(
          repoRoot,
          packageName,
          concurrency: packageTestJobs,
        ),
      for (final theme in externalThemes) ...[
        RunStep(
          id: '${theme.packageName}.analyze',
          command: [...flutter, 'analyze', '--no-pub'],
          workingDirectory: theme.directory.path,
          dependencies: ['scenes.generate_${theme.packageName}'],
        ),
        ?_createFlutterTestStep(
          repoRoot,
          theme.directory,
          theme.packageName,
          dependencies: ['scenes.generate_${theme.packageName}'],
          concurrency: packageTestJobs,
        ),
      ],
      RunStep(
        id: 'dbus.smoke',
        command: [
          'bash',
          '${repoRoot.path}/scripts/debug-dbus.sh',
          ...flutter,
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

RunStep? _createFlutterTestStep(
  Directory repoRoot,
  Directory directory,
  String packageName, {
  required List<String> dependencies,
  required int concurrency,
}) {
  final testDirectory = Directory(getJoinedPath(directory.path, 'test'));
  final hasTests =
      testDirectory.existsSync() &&
      testDirectory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .any((file) => file.path.endsWith('_test.dart'));
  if (!hasTests) return null;
  return RunStep(
    id: '$packageName.test',
    command: [
      ...getFlutterCommand(repoRoot),
      'test',
      '--no-pub',
      '--concurrency=$concurrency',
    ],
    workingDirectory: directory.path,
    dependencies: dependencies,
  );
}

RunStep _createDartTestStep(
  Directory repoRoot,
  String packageName, {
  required int concurrency,
}) {
  return RunStep(
    id: '$packageName.test',
    command: [
      ...getDartCommand(repoRoot),
      'test',
      '--concurrency=$concurrency',
    ],
    workingDirectory: 'packages/$packageName',
    dependencies: const ['workspace.pub_get'],
  );
}
