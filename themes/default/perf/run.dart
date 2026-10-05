import 'dart:convert';
import 'dart:io';

import '../../../tool/src/sdk_commands.dart';
import '../../../tool/src/theme_host.dart';
import '../../../tool/src/theme_project.dart';

Future<void> main(List<String> arguments) async {
  try {
    final output = Directory(Platform.environment['AKARI_PERF_OUTPUT_DIR']!);
    if (arguments
        .skip(1)
        .any((argument) => argument == '--help' || argument == '-h')) {
      stdout.writeln(
        'Default theme perf: verify [--cycles COUNT] [--baseline PATH] | trace',
      );
      await _writeResult(output, []);
      return;
    }
    final options = _getOptions(arguments);
    final themeDirectory = File.fromUri(Platform.script).parent.parent;
    final repoRoot = themeDirectory.parent.parent;
    final theme = getThemePackage(themeDirectory);
    final host = Directory(
      '${repoRoot.path}/${getThemeHostDirectory(theme, preview: true)}-perf',
    );
    // This theme's integration fixture runs the shared greeter application.
    // Its test dependencies and entrypoints belong to this perf host only.
    createThemeHost(
      repoRoot: repoRoot,
      theme: theme,
      output: host,
      preview: true,
      devDependencies: {
        'flutter_test': {'sdk': 'flutter'},
        'integration_test': {'sdk': 'flutter'},
      },
    );
    final flutter = getFlutterCommand(repoRoot);
    final dart = getDartCommand(repoRoot);
    await _execute([...flutter, 'pub', 'get'], host);
    final artifacts = <Map<String, String>>[];
    final reports = <String>[];
    final measurements = options.trace ? 1 : options.cycles;
    for (var cycle = 1; cycle <= measurements; cycle++) {
      final reportName = 'scene_report_$cycle.json';
      final reportPath = '${output.path}/$reportName';
      final timelinePath = '${output.path}/scene_interactions_timeline.json';
      await _execute([
        ...flutter,
        'drive',
        '-d',
        'linux',
        '--profile',
        '--no-dds',
        '--dart-define=AKARI_BACKEND=demo',
        '--dart-define=AKARI_PERF_REPORT_PATH=$reportPath',
        if (options.trace) ...[
          '--dart-define=AKARI_PERF_TRACE_TIMELINE=true',
          '--dart-define=AKARI_PERF_TIMELINE_PATH=$timelinePath',
        ],
        '--driver=${themeDirectory.path}/perf/test_driver/integration_test.dart',
        '--target=${themeDirectory.path}/perf/integration_test/scene_performance_test.dart',
      ], host);
      reports.add(reportPath);
      artifacts.add({'name': 'cycle_$cycle', 'path': reportName});
    }

    if (options.trace) {
      artifacts.add({
        'name': 'timeline',
        'path': 'scene_interactions_timeline.json',
      });
      // Publish diagnostics before analysis so failures still leave usable data.
      await _writeResult(output, artifacts);
      await _execute([
        ...dart,
        'run',
        'perf/summarize_timeline.dart',
        '--input',
        '${output.path}/scene_interactions_timeline.json',
      ], themeDirectory);
      return;
    }

    await _execute([
      ...dart,
      'run',
      'perf/aggregate_perf.dart',
      '--output',
      '${output.path}/scene_report.json',
      for (final report in reports) ...['--input', report],
    ], themeDirectory);
    artifacts.add({'name': 'report', 'path': 'scene_report.json'});
    await _writeResult(output, artifacts);
    await _execute([
      ...dart,
      'run',
      'perf/compare_perf.dart',
      '--baseline',
      options.baseline,
      '--candidate',
      '${output.path}/scene_report.json',
    ], themeDirectory);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  } on _CommandFailure catch (error) {
    exitCode = error.exitCode;
  }
}

({bool trace, int cycles, String baseline}) _getOptions(
  List<String> arguments,
) {
  if (arguments.isEmpty ||
      !const {'verify', 'trace'}.contains(arguments.first)) {
    throw const FormatException(
      'Usage: perf/run.dart verify [--cycles COUNT] [--baseline PATH] | trace',
    );
  }
  final trace = arguments.first == 'trace';
  final values = <String, String>{};
  for (var index = 1; index < arguments.length; index++) {
    final option = arguments[index];
    if (trace || !const {'--cycles', '--baseline'}.contains(option)) {
      throw FormatException('Unknown default theme perf option: $option');
    }
    if (values.containsKey(option)) {
      throw FormatException('Duplicate $option option.');
    }
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      throw FormatException('Missing value for $option.');
    }
    values[option] = arguments[++index];
  }
  final cycles = int.tryParse(values['--cycles'] ?? '3');
  if (cycles == null || cycles < 3) {
    throw const FormatException('--cycles must be an integer of at least 3.');
  }
  return (
    trace: trace,
    cycles: cycles,
    baseline: values['--baseline'] ?? 'perf/baselines/default.json',
  );
}

Future<void> _execute(List<String> command, Directory directory) async {
  final process = await Process.start(
    command.first,
    command.skip(1).toList(),
    workingDirectory: directory.path,
    mode: ProcessStartMode.inheritStdio,
  );
  final status = await process.exitCode;
  if (status != 0) throw _CommandFailure(status);
}

Future<void> _writeResult(
  Directory output,
  List<Map<String, String>> artifacts,
) =>
    File('${output.path}/result.json')
        .writeAsString(jsonEncode({'version': 1, 'artifacts': artifacts}));

class _CommandFailure implements Exception {
  const _CommandFailure(this.exitCode);
  final int exitCode;
}
