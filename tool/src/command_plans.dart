import 'dart:convert';
import 'dart:io';

import 'build_links.dart';
import 'run_report.dart';
import 'sdk_commands.dart';
import 'theme_host.dart';
import 'theme_project.dart';
import 'theme_perf.dart';

/// Describes commands without executing them, allowing dry-run to show the same
/// dependency plan used by the runner. Theme metadata is resolved by the caller;
/// steps may then trust the selected package's canonical identity.
List<RunStep> buildStepsFor(
  String command,
  Directory repoRoot,
  String runDirectory, {
  String buildTarget = 'linux',
  String buildMode = 'release',
  ThemePackage? selectedTheme,
  bool preview = false,
  int? jobs,
  String backendMode = 'mock',
  List<String> themeArguments = const [],
  Map<String, Object?>? displayProfile,
  String swayBackend = 'wayland',
}) {
  return switch (command) {
    'build' ||
    'run' ||
    'run sway' ||
    'preview' ||
    'run studio' => _buildThemeSteps(
      command,
      repoRoot,
      runDirectory,
      selectedTheme!,
      buildTarget: buildTarget,
      buildMode: buildMode,
      preview: preview,
      jobs: jobs,
      backendMode: backendMode,
      displayProfile: displayProfile,
      swayBackend: swayBackend,
    ),
    'verify' => _buildVerificationSteps(repoRoot, runDirectory, selectedTheme),
    'verify-perf' || 'trace-perf' => _buildPerformanceSteps(
      command,
      repoRoot,
      runDirectory,
      selectedTheme!,
      themeArguments,
    ),
    'generate-scenes' => _sceneGenerationSteps(
      repoRoot,
      selectedTheme == null ? null : [selectedTheme],
    ),
    _ => throw StateError('No step plan for command $command.'),
  };
}

List<RunStep> _buildThemeSteps(
  String command,
  Directory repoRoot,
  String runDirectory,
  ThemePackage theme, {
  required String buildTarget,
  required String buildMode,
  required bool preview,
  required int? jobs,
  required String backendMode,
  required Map<String, Object?>? displayProfile,
  required String swayBackend,
}) {
  final studio = command == 'run studio';
  final sway = command == 'run sway';
  final greeter = command == 'run' || sway;
  final demo = preview || studio;
  final live = command != 'build';
  final transport = greeter ? backendMode : 'real';
  final hostDirectory = getThemeHostDirectory(
    theme,
    preview: demo,
    studio: studio,
  );
  return [
    if (!demo)
      RunStep(
        id: 'backend.build',
        command: [
          'cargo',
          'build',
          '--locked',
          '--target-dir',
          'target/akari-$transport',
          if (buildMode != 'debug') '--release',
          if (greeter && backendMode == 'mock') ...['--features', 'mock'],
          if (jobs != null) ...['--jobs', '$jobs'],
        ],
        workingDirectory: 'backend',
        dependencies: const [],
      ),
    RunStep(
      id: 'theme.pub_get',
      command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
      workingDirectory: theme.directory.path,
      dependencies: const [],
    ),
    ..._sceneGenerationSteps(repoRoot, [theme]),
    RunStep(
      id: 'theme.host.generate',
      command: [
        ...getDartCommand(repoRoot),
        'tool/theme_host.dart',
        theme.directory.path,
        _join(repoRoot.path, hostDirectory),
        if (studio) '--studio' else if (preview) '--preview',
      ],
      action: () => createThemeHost(
        repoRoot: repoRoot,
        theme: theme,
        output: Directory(_join(repoRoot.path, hostDirectory)),
        preview: demo,
        studio: studio,
      ),
    ),
    RunStep(
      id: 'theme.host.pub_get',
      command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
      workingDirectory: hostDirectory,
    ),
    if (!live) ...[
      RunStep(
        id: 'flutter.build_$buildTarget',
        command: [
          ...getFlutterCommand(repoRoot),
          'build',
          buildTarget,
          '--$buildMode',
          '--no-pub',
          '--dart-define=AKARI_BACKEND=${demo ? 'demo' : 'real'}',
        ],
        workingDirectory: hostDirectory,
        environment: {if (jobs != null) 'AKARI_BUILD_JOBS': '$jobs'},
      ),
      if (buildTarget == 'linux')
        // Publishing requires both artifacts. The backend branch can run in
        // parallel, so the previous frontend step alone is not sufficient.
        RunStep(
          id: 'build.links',
          command: [
            ...getDartCommand(repoRoot),
            'tool/build_links.dart',
            repoRoot.path,
            theme.directory.path,
            buildMode,
          ],
          dependencies: const ['backend.build', 'flutter.build_linux'],
          action: () => updateBuildLinks(repoRoot, theme, buildMode),
        ),
    ] else
      RunStep(
        id:
            'theme.${switch (command) {
              'run studio' => 'studio',
              'run sway' => 'sway',
              _ => command,
            }}',
        command: [
          if (sway) ...[
            'python3',
            _join(repoRoot.path, 'scripts/sway-session.py'),
            '--log-dir',
            _join(repoRoot.path, '$runDirectory/sway'),
            '--backend',
            swayBackend,
            '--',
          ],
          if (!demo) ...['bash', _join(repoRoot.path, 'scripts/debug-dbus.sh')],
          ...getDartCommand(repoRoot),
          _join(repoRoot.path, 'tool/theme_session.dart'),
          theme.directory.path,
          _join(repoRoot.path, hostDirectory),
          buildMode,
          demo ? 'demo' : 'real',
        ],
        workingDirectory: hostDirectory,
        dependencies: [if (!demo) 'backend.build', 'theme.host.pub_get'],
        interactive: true,
        environment: {
          'AKARI_DISPLAY_MODE': studio ? 'single' : 'mirror',
          'AKARI_WINDOW_MODE':
              Platform.environment['AKARI_WINDOW_MODE'] ??
              (demo ? 'windowed' : 'fullscreen'),
          if (jobs != null) 'AKARI_BUILD_JOBS': '$jobs',
          if (sway) 'AKARI_DISPLAY_PROFILE_JSON': jsonEncode(displayProfile!),
          if (!demo) ...{
            'AKARI_BACKEND_MODE': backendMode,
            'AKARI_BACKEND_BIN': _join(
              repoRoot.path,
              'backend/target/akari-$transport/${buildMode == 'debug' ? 'debug' : 'release'}/backend',
            ),
            'AKARI_LOG_DIR': _join(repoRoot.path, '$runDirectory/dbus'),
          },
        },
      ),
  ];
}

List<RunStep> _buildVerificationSteps(
  Directory repoRoot,
  String runDirectory,
  ThemePackage? selectedTheme,
) {
  final themes = selectedTheme == null
      ? findThemePackages(repoRoot)
      : [selectedTheme];
  return [
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
    ..._sceneGenerationSteps(repoRoot, themes),
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
        if (selectedTheme == null) 'tool/dev_main.dart',
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
        'AKARI_LOG_DIR': _join(repoRoot.path, '$runDirectory/dbus'),
      },
    ),
  ];
}

List<RunStep> _buildPerformanceSteps(
  String command,
  Directory repoRoot,
  String runDirectory,
  ThemePackage theme,
  List<String> themeArguments,
) {
  final operation = command == 'verify-perf' ? 'verify' : 'trace';
  final entrypoint = getThemePerfCommand(theme, operation);
  final executable = switch (entrypoint.first) {
    'dart' => getDartCommand(repoRoot),
    'flutter' => getFlutterCommand(repoRoot),
    final executable => [executable],
  };
  return [
    RunStep(
      id: 'theme.pub_get',
      command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
      workingDirectory: theme.directory.path,
    ),
    ..._sceneGenerationSteps(repoRoot, [theme]),
    RunStep(
      id: 'theme.perf.$operation',
      command: [...executable, ...entrypoint.skip(1), ...themeArguments],
      workingDirectory: theme.directory.path,
      environment: {
        'AKARI_PERF_OUTPUT_DIR': _join(repoRoot.path, '$runDirectory/perf'),
      },
    ),
  ];
}

List<RunStep> _sceneGenerationSteps(
  Directory repoRoot, [
  List<ThemePackage>? themes,
]) {
  final discoveredThemes = themes ?? findThemePackages(repoRoot);
  return [
    for (final theme in discoveredThemes)
      RunStep(
        id: 'scenes.generate_${theme.packageName}',
        command: [...getDartCommand(repoRoot), 'run', 'build_runner', 'build'],
        workingDirectory: theme.directory.path,
      ),
  ];
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
        Directory(_join(repoRoot.path, 'packages/$packageName')),
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
  final testDirectory = Directory(_join(directory.path, 'test'));
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

Map<String, String> artifactPathsFor(
  String command,
  String runDirectory, {
  String buildTarget = 'linux',
  String buildMode = 'release',
  ThemePackage? selectedTheme,
  bool preview = false,
  String backendMode = 'real',
}) {
  final hostDirectory = selectedTheme == null
      ? null
      : getThemeHostDirectory(
          selectedTheme,
          preview: preview,
          studio: command == 'run studio',
        );
  return switch (command) {
    'build' || 'run' || 'run sway' || 'preview' || 'run studio' => {
      if (!preview && command != 'run studio')
        'backend_executable':
            'backend/target/akari-$backendMode/${buildMode == 'debug' ? 'debug' : 'release'}/backend',
      'host_project': hostDirectory!,
      'build_directory': '$hostDirectory/build/$buildTarget',
      if (buildTarget == 'linux')
        'executable': getLinuxExecutablePath(hostDirectory, buildMode),
      if (command == 'build' && buildTarget == 'linux')
        ...getBuildLinkPaths(selectedTheme!),
      if (command == 'run sway') ...{
        'display_report': '$runDirectory/sway/display-report.json',
        'display_snapshot': '$runDirectory/sway/outputs.json',
        'screenshots': '$runDirectory/sway/screenshots',
        'sway_log': '$runDirectory/sway/sway.log',
        'flutter_log': '$runDirectory/sway/flutter.log',
      },
    },
    'verify-perf' || 'trace-perf' => {
      'performance_output': '$runDirectory/perf',
      'performance_result': '$runDirectory/perf/result.json',
    },
    _ => const {},
  };
}

String _join(String base, String relative) {
  return '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
}
