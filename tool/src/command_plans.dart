import 'dart:ffi';
import 'dart:io';

import 'run_report.dart';
import 'theme_project.dart';

List<RunStep> buildStepsFor(
  String command,
  int cycles,
  Directory repoRoot,
  String runDirectory, {
  String buildTarget = 'linux',
  String buildMode = 'release',
  ThemePackage? buildTheme,
  bool preview = false,
}) {
  switch (command) {
    case 'build':
      final theme = buildTheme!;
      final hostDirectory = '$runDirectory/theme_host';
      return [
        _step('theme.pub_get', [
          ..._flutterCommand(repoRoot),
          'pub',
          'get',
        ], workingDirectory: theme.directory.path),
        ..._sceneGenerationSteps(repoRoot, [theme]),
        _step('theme.host.generate', [
          ...getDartCommand(repoRoot),
          'tool/theme_host.dart',
          theme.directory.path,
          _join(repoRoot.path, hostDirectory),
          if (preview) '--preview',
        ]),
        _step('theme.host.pub_get', [
          ..._flutterCommand(repoRoot),
          'pub',
          'get',
        ], workingDirectory: hostDirectory),
        _step('flutter.build_$buildTarget', [
          ..._flutterCommand(repoRoot),
          'build',
          buildTarget,
          '--$buildMode',
          '--dart-define=MOZAIS_BACKEND=${preview ? 'demo' : 'real'}',
        ], workingDirectory: hostDirectory),
        if (preview)
          _step('theme.preview', [
            _join(
              repoRoot.path,
              getLinuxExecutablePath(runDirectory, buildMode),
            ),
          ], workingDirectory: hostDirectory),
      ];
    case 'verify':
      final themes = findThemePackages(repoRoot);
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
        ..._sceneGenerationSteps(repoRoot, themes),
        _step('flutter.analyze', [..._flutterCommand(repoRoot), 'analyze']),
        _step('flutter.test', [..._flutterCommand(repoRoot), 'test']),
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
          ..._flutterCommand(repoRoot),
          'analyze',
        ], workingDirectory: 'packages/scene'),
        _step('scene.test', [
          ..._flutterCommand(repoRoot),
          'test',
        ], workingDirectory: 'packages/scene'),
        _step('greeter_ui.analyze', [
          ..._flutterCommand(repoRoot),
          'analyze',
        ], workingDirectory: 'packages/greeter_ui'),
        _step('greeter_ui.test', [
          ..._flutterCommand(repoRoot),
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
      final steps = <RunStep>[..._sceneGenerationSteps(repoRoot)];
      final flutter = _flutterCommand(repoRoot);
      for (var cycle = 1; cycle <= cycles; cycle++) {
        final cycleReport = '$runDirectory/perf/scene_report_$cycle.json';
        steps.add(
          _step('performance.drive_$cycle', [
            ...flutter,
            'drive',
            '-d',
            'linux',
            '--profile',
            '--no-dds',
            '--dart-define=MOZAIS_PERF_REPORT_PATH=$cycleReport',
            '--driver=test_driver/integration_test.dart',
            '--target=integration_test/performance/scene_performance_test.dart',
          ]),
        );
      }
      steps.add(
        _step('performance.aggregate', [
          ...getDartCommand(repoRoot),
          'run',
          'tool/perf/aggregate_perf.dart',
          '--output',
          'build/perf/scene_report.json',
          for (var cycle = 1; cycle <= cycles; cycle++) ...[
            '--input',
            '$runDirectory/perf/scene_report_$cycle.json',
          ],
        ]),
      );
      steps.add(
        _step('performance.compare', [
          ...getDartCommand(repoRoot),
          'run',
          'tool/perf/compare_perf.dart',
          '--baseline',
          'tool/perf/baselines/default.json',
          '--candidate',
          'build/perf/scene_report.json',
        ]),
      );
      return steps;
    case 'generate-scenes':
      return _sceneGenerationSteps(repoRoot);
    case 'trace-perf':
      final timeline = '$runDirectory/perf/scene_interactions_timeline.json';
      return [
        ..._sceneGenerationSteps(repoRoot),
        _step('performance.trace', [
          ..._flutterCommand(repoRoot),
          'drive',
          '-d',
          'linux',
          '--profile',
          '--no-dds',
          '--dart-define=MOZAIS_PERF_TRACE_TIMELINE=true',
          '--dart-define=MOZAIS_PERF_TIMELINE_PATH=$timeline',
          '--driver=test_driver/integration_test.dart',
          '--target=integration_test/performance/scene_performance_test.dart',
        ]),
        _step('performance.summarize_trace', [
          ...getDartCommand(repoRoot),
          'run',
          'tool/perf/summarize_timeline.dart',
          '--input',
          timeline,
        ]),
      ];
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
  final flutter = _flutterCommand(repoRoot);

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
}) {
  return RunStep(
    id: id,
    command: command,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

List<String> _flutterCommand(Directory repoRoot) {
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
}) {
  return switch (command) {
    'build' => {
      'host_project': '$runDirectory/theme_host',
      'build_directory': '$runDirectory/theme_host/build/$buildTarget',
      if (buildTarget == 'linux')
        'executable': getLinuxExecutablePath(runDirectory, buildMode),
    },
    'verify-perf' => {
      'performance_report': 'build/perf/scene_report.json',
      'performance_raw_reports': '$runDirectory/perf',
    },
    'trace-perf' => {
      'timeline': '$runDirectory/perf/scene_interactions_timeline.json',
    },
    _ => const {},
  };
}

String getLinuxExecutablePath(String runDirectory, String buildMode) {
  final architecture = switch (Abi.current()) {
    Abi.linuxX64 => 'x64',
    Abi.linuxArm64 => 'arm64',
    _ => throw UnsupportedError('Linux builds require an x64 or arm64 host.'),
  };
  return '$runDirectory/theme_host/build/linux/$architecture/$buildMode/bundle/greeter';
}

String _join(String base, String relative) {
  return '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
}
