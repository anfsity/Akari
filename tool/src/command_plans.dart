import 'dart:io';

import 'run_report.dart';
import 'theme_catalog.dart';

List<RunStep> buildStepsFor(
  String command,
  int cycles,
  Directory repoRoot,
  String runDirectory, {
  String buildTarget = 'linux',
  String? buildMode,
}) {
  switch (command) {
    case 'build':
      final themes = findThemePackages(repoRoot);
      return [
        _step('themes.catalog.generate', [
          ..._dartCommand(repoRoot),
          'run',
          'tool/theme_catalog.dart',
          '--write',
        ]),
        _step('themes.catalog.pub_get', [
          ..._flutterCommand(repoRoot),
          'pub',
          'get',
        ], workingDirectory: 'packages/mozais_theme_catalog'),
        _step('app.pub_get', [..._flutterCommand(repoRoot), 'pub', 'get']),
        for (final theme in themes)
          _step('themes.pub_get_${theme.packageName}', [
            ..._flutterCommand(repoRoot),
            'pub',
            'get',
          ], workingDirectory: theme.relativePath),
        ..._sceneGenerationSteps(repoRoot, themes),
        _step('flutter.build_$buildTarget', [
          ..._flutterCommand(repoRoot),
          'build',
          buildTarget,
          if (buildMode != null) '--$buildMode',
        ]),
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
          ..._dartCommand(repoRoot),
          'analyze',
        ], workingDirectory: 'packages/mozais_scene_schema'),
        _step('scene_schema.test', [
          ..._dartCommand(repoRoot),
          'test',
        ], workingDirectory: 'packages/mozais_scene_schema'),
        _step('scene_codegen.analyze', [
          ..._dartCommand(repoRoot),
          'analyze',
        ], workingDirectory: 'packages/mozais_scene_codegen'),
        _step('scene_codegen.test', [
          ..._dartCommand(repoRoot),
          'test',
        ], workingDirectory: 'packages/mozais_scene_codegen'),
        _step('scene.analyze', [
          ..._flutterCommand(repoRoot),
          'analyze',
        ], workingDirectory: 'packages/mozais_scene'),
        _step('scene.test', [
          ..._flutterCommand(repoRoot),
          'test',
        ], workingDirectory: 'packages/mozais_scene'),
        _step('greeter_ui.analyze', [
          ..._flutterCommand(repoRoot),
          'analyze',
        ], workingDirectory: 'packages/mozais_greeter_ui'),
        _step('greeter_ui.test', [
          ..._flutterCommand(repoRoot),
          'test',
        ], workingDirectory: 'packages/mozais_greeter_ui'),
        ..._getThemeVerificationSteps(repoRoot, themes),
        _step(
          'dbus.smoke',
          [
            'bash',
            'scripts/debug-dbus.sh',
            ..._dartCommand(repoRoot),
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
          ..._dartCommand(repoRoot),
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
          ..._dartCommand(repoRoot),
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
          ..._dartCommand(repoRoot),
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
        ..._dartCommand(repoRoot),
        'run',
        'build_runner',
        'build',
      ], workingDirectory: theme.relativePath),
  ];
}

List<RunStep> _getThemeVerificationSteps(
  Directory repoRoot,
  List<ThemePackage> themes,
) {
  final packageNames = [
    'mozais_greeter_components',
    'mozais_theme_sdk',
    'mozais_theme_catalog',
    ...themes.map((theme) => theme.packageName),
  ];
  return [
    for (final packageName in packageNames)
      ..._getFlutterPackageVerificationSteps(repoRoot, packageName),
  ];
}

List<RunStep> _getFlutterPackageVerificationSteps(
  Directory repoRoot,
  String packageName,
) {
  final workingDirectory = 'packages/$packageName';
  final testDirectory = Directory(
    _join(repoRoot.path, '$workingDirectory/test'),
  );
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
    ], workingDirectory: workingDirectory),
    if (hasTests)
      _step('$packageName.test', [
        ...flutter,
        'test',
      ], workingDirectory: workingDirectory),
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
  return customFlutter == null || customFlutter.isEmpty
      ? ['fvm', 'flutter']
      : [_resolveSdkBinary(customFlutter, repoRoot)];
}

List<String> _dartCommand(Directory repoRoot) {
  final customDart = Platform.environment['MOZAIS_DART_BIN'];
  if (customDart != null && customDart.isNotEmpty) {
    return [_resolveSdkBinary(customDart, repoRoot)];
  }
  final customFlutter = Platform.environment['MOZAIS_FLUTTER_BIN'];
  if (customFlutter != null && customFlutter.isNotEmpty) {
    final flutterPath = _resolveSdkBinary(customFlutter, repoRoot);
    return [_join(File(flutterPath).parent.path, 'dart')];
  }
  return ['fvm', 'dart'];
}

String _resolveSdkBinary(String binary, Directory repoRoot) {
  final file = File(binary);
  return file.isAbsolute ? binary : _join(repoRoot.path, binary);
}

Map<String, String> artifactPathsFor(String command, String runDirectory) {
  return switch (command) {
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

String _join(String base, String relative) {
  return '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
}
