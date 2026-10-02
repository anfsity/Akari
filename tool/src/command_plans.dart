import 'dart:io';

import 'build_links.dart';
import 'run_report.dart';
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
}) {
  switch (command) {
    case 'build':
    case 'run':
    case 'preview':
      final live = command != 'build';
      final transport = command == 'run' ? backendMode : 'real';
      final theme = selectedTheme!;
      final hostDirectory = getThemeHostDirectory(theme, preview: preview);
      return [
        if (!preview)
          _step(
            'backend.build',
            [
              'cargo',
              'build',
              '--locked',
              '--target-dir',
              'target/mozais-$transport',
              if (buildMode != 'debug') '--release',
              if (command == 'run' && backendMode == 'mock') ...[
                '--features',
                'mock',
              ],
              if (jobs != null) ...['--jobs', '$jobs'],
            ],
            workingDirectory: 'backend',
            dependencies: const [],
          ),
        _step(
          'theme.pub_get',
          [...getFlutterCommand(repoRoot), 'pub', 'get'],
          workingDirectory: theme.directory.path,
          dependencies: const [],
        ),
        ..._sceneGenerationSteps(repoRoot, [theme]),
        _step('theme.host.generate', [
          ...getDartCommand(repoRoot),
          'tool/theme_host.dart',
          theme.directory.path,
          _join(repoRoot.path, hostDirectory),
          if (preview) '--preview',
        ]),
        _step('theme.host.pub_get', [
          ...getFlutterCommand(repoRoot),
          'pub',
          'get',
        ], workingDirectory: hostDirectory),
        if (!live)
          _step(
            'flutter.build_$buildTarget',
            [
              ...getFlutterCommand(repoRoot),
              'build',
              buildTarget,
              '--$buildMode',
              '--dart-define=MOZAIS_BACKEND=${preview ? 'demo' : 'real'}',
            ],
            workingDirectory: hostDirectory,
            environment: {if (jobs != null) 'MOZAIS_BUILD_JOBS': '$jobs'},
          ),
        if (!live && buildTarget == 'linux')
          // Publishing requires both artifacts. The backend branch can run in
          // parallel, so the previous frontend step alone is not sufficient.
          _step(
            'build.links',
            [
              ...getDartCommand(repoRoot),
              'tool/build_links.dart',
              repoRoot.path,
              theme.directory.path,
              buildMode,
            ],
            dependencies: const ['backend.build', 'flutter.build_linux'],
          ),
        if (live)
          _step(
            'theme.$command',
            [
              if (!preview) ...[
                'bash',
                _join(repoRoot.path, 'scripts/debug-dbus.sh'),
              ],
              ...getDartCommand(repoRoot),
              _join(repoRoot.path, 'tool/theme_session.dart'),
              theme.directory.path,
              _join(repoRoot.path, hostDirectory),
              buildMode,
              preview ? 'demo' : 'real',
            ],
            workingDirectory: hostDirectory,
            dependencies: [if (!preview) 'backend.build', 'theme.host.pub_get'],
            interactive: true,
            environment: {
              if (jobs != null) 'MOZAIS_BUILD_JOBS': '$jobs',
              if (!preview) ...{
                'MOZAIS_BACKEND_MODE': backendMode,
                'MOZAIS_BACKEND_BIN': _join(
                  repoRoot.path,
                  'backend/target/mozais-$transport/${buildMode == 'debug' ? 'debug' : 'release'}/backend',
                ),
                'MOZAIS_LOG_DIR': _join(repoRoot.path, '$runDirectory/dbus'),
              },
            },
          ),
      ];
    case 'verify':
      final themes = selectedTheme == null
          ? findThemePackages(repoRoot)
          : [selectedTheme];
      return [
        _step('toolchain.check', ['bash', 'scripts/check-toolchain.sh']),
        _step('backend.format', [
          'cargo',
          'fmt',
          '--all',
          '--',
          '--check',
        ], workingDirectory: 'backend'),
        _step('backend.check', [
          'cargo',
          'check',
          '--locked',
        ], workingDirectory: 'backend'),
        _step('backend.test', [
          'cargo',
          'test',
          '--locked',
          '--',
          '--test-threads=1',
        ], workingDirectory: 'backend'),
        _step('backend.test_mock', [
          'cargo',
          'test',
          '--locked',
          '--features',
          'mock',
          '--',
          '--test-threads=1',
        ], workingDirectory: 'backend'),
        for (final theme in themes)
          _step('${theme.packageName}.pub_get', [
            ...getFlutterCommand(repoRoot),
            'pub',
            'get',
          ], workingDirectory: theme.directory.path),
        ..._sceneGenerationSteps(repoRoot, themes),
        _step('flutter.analyze', [
          ...getFlutterCommand(repoRoot),
          'analyze',
          'lib',
          'test',
          'tool/src',
          'tool/mozais.dart',
          'tool/theme_host.dart',
          'tool/theme_session.dart',
          'tool/dbus_gateway_smoke.dart',
          if (selectedTheme == null) 'tool/dev_main.dart',
        ]),
        _step('flutter.test', [...getFlutterCommand(repoRoot), 'test']),
        _step('scene_schema.analyze', [
          ...getDartCommand(repoRoot),
          'analyze',
        ], workingDirectory: 'packages/scene_schema'),
        _step('scene_schema.test', [
          ...getDartCommand(repoRoot),
          'test',
        ], workingDirectory: 'packages/scene_schema'),
        _step('scene_codegen.analyze', [
          ...getDartCommand(repoRoot),
          'analyze',
        ], workingDirectory: 'packages/scene_codegen'),
        _step('scene_codegen.test', [
          ...getDartCommand(repoRoot),
          'test',
        ], workingDirectory: 'packages/scene_codegen'),
        _step('scene.analyze', [
          ...getFlutterCommand(repoRoot),
          'analyze',
        ], workingDirectory: 'packages/scene'),
        _step('scene.test', [
          ...getFlutterCommand(repoRoot),
          'test',
        ], workingDirectory: 'packages/scene'),
        _step('greeter_ui.analyze', [
          ...getFlutterCommand(repoRoot),
          'analyze',
        ], workingDirectory: 'packages/greeter_ui'),
        _step('greeter_ui.test', [
          ...getFlutterCommand(repoRoot),
          'test',
        ], workingDirectory: 'packages/greeter_ui'),
        ..._getThemeVerificationSteps(repoRoot, themes),
        _step(
          'dbus.smoke',
          [
            'bash',
            'scripts/debug-dbus.sh',
            ...getDartCommand(repoRoot),
            'run',
            'tool/dbus_gateway_smoke.dart',
          ],
          environment: {
            'MOZAIS_LOG_DIR': _join(repoRoot.path, '$runDirectory/dbus'),
          },
        ),
      ];
    case 'verify-perf':
    case 'trace-perf':
      final theme = selectedTheme!;
      final operation = command == 'verify-perf' ? 'verify' : 'trace';
      final entrypoint = getThemePerfCommand(theme, operation);
      final executable = switch (entrypoint.first) {
        'dart' => getDartCommand(repoRoot),
        'flutter' => getFlutterCommand(repoRoot),
        final executable => [executable],
      };
      return [
        _step('theme.pub_get', [
          ...getFlutterCommand(repoRoot),
          'pub',
          'get',
        ], workingDirectory: theme.directory.path),
        ..._sceneGenerationSteps(repoRoot, [theme]),
        _step(
          'theme.perf.$operation',
          [...executable, ...entrypoint.skip(1), ...themeArguments],
          workingDirectory: theme.directory.path,
          environment: {
            'MOZAIS_PERF_OUTPUT_DIR': _join(
              repoRoot.path,
              '$runDirectory/perf',
            ),
          },
        ),
      ];
    case 'generate-scenes':
      return _sceneGenerationSteps(
        repoRoot,
        selectedTheme == null ? null : [selectedTheme],
      );
    default:
      throw StateError('No step plan for command $command.');
  }
}

List<RunStep> _sceneGenerationSteps(
  Directory repoRoot, [
  List<ThemePackage>? themes,
]) {
  final discoveredThemes = themes ?? findThemePackages(repoRoot);
  return [
    for (final theme in discoveredThemes)
      _step('scenes.generate_${theme.packageName}', [
        ...getDartCommand(repoRoot),
        'run',
        'build_runner',
        'build',
      ], workingDirectory: theme.directory.path),
  ];
}

List<RunStep> _getThemeVerificationSteps(
  Directory repoRoot,
  List<ThemePackage> themes,
) {
  final packageNames = ['greeter_components', 'theme_sdk'];
  return [
    for (final packageName in packageNames)
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
    _step('$packageName.analyze', [
      ...flutter,
      'analyze',
    ], workingDirectory: directory.path),
    if (hasTests)
      _step('$packageName.test', [
        ...flutter,
        'test',
      ], workingDirectory: directory.path),
  ];
}

RunStep _step(
  String id,
  List<String> command, {
  String workingDirectory = '.',
  Map<String, String> environment = const {},
  List<String>? dependencies,
  bool interactive = false,
}) {
  return RunStep(
    id: id,
    command: command,
    workingDirectory: workingDirectory,
    environment: environment,
    dependencies: dependencies,
    interactive: interactive,
  );
}

List<String> getFlutterCommand(Directory repoRoot) {
  final customFlutter = Platform.environment['MOZAIS_FLUTTER_BIN'];
  if (customFlutter != null && customFlutter.isNotEmpty) {
    return [_resolveSdkBinary(customFlutter, repoRoot)];
  }
  final localFlutter = File(
    _join(repoRoot.path, '.fvm/flutter_sdk/bin/flutter'),
  );
  return localFlutter.existsSync() ? [localFlutter.path] : ['fvm', 'flutter'];
}

List<String> getDartCommand(Directory repoRoot) {
  final customDart = Platform.environment['MOZAIS_DART_BIN'];
  if (customDart != null && customDart.isNotEmpty) {
    return [_resolveSdkBinary(customDart, repoRoot)];
  }
  final customFlutter = Platform.environment['MOZAIS_FLUTTER_BIN'];
  if (customFlutter != null && customFlutter.isNotEmpty) {
    final flutterPath = _resolveSdkBinary(customFlutter, repoRoot);
    return [_join(File(flutterPath).parent.path, 'dart')];
  }
  final localDart = File(_join(repoRoot.path, '.fvm/flutter_sdk/bin/dart'));
  return localDart.existsSync() ? [localDart.path] : ['fvm', 'dart'];
}

String _resolveSdkBinary(String binary, Directory repoRoot) {
  final file = File(binary);
  return file.isAbsolute ? binary : _join(repoRoot.path, binary);
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
      : getThemeHostDirectory(selectedTheme, preview: preview);
  return switch (command) {
    'build' || 'run' || 'preview' => {
      if (!preview)
        'backend_executable':
            'backend/target/mozais-$backendMode/${buildMode == 'debug' ? 'debug' : 'release'}/backend',
      'host_project': hostDirectory!,
      'build_directory': '$hostDirectory/build/$buildTarget',
      if (buildTarget == 'linux')
        'executable': getLinuxExecutablePath(hostDirectory, buildMode),
      if (command == 'build' && buildTarget == 'linux')
        ...getBuildLinkPaths(selectedTheme!),
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
