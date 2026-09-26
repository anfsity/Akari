import 'dart:io';

import 'src/command_plans.dart';
import 'src/run_report.dart';

const _commands = {
  'build',
  'verify',
  'verify-perf',
  'generate-scenes',
  'trace-perf',
};
const _minimumPerfCycles = 3;

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty || arguments.first == '--help') {
      _writeUsage();
      return;
    }

    final command = arguments.first;
    if (!_commands.contains(command)) {
      throw FormatException('Unknown command: $command');
    }
    if (arguments
        .skip(1)
        .any((argument) => argument == '-h' || argument == '--help')) {
      _writeUsage(command);
      return;
    }

    final options = _parseOptions(command, arguments.skip(1).toList());
    final repoRoot = _findRepoRoot();
    final runDirectory = await _createRunDirectory(
      repoRoot,
      reserve: !options.dryRun,
    );
    final steps = buildStepsFor(
      command,
      options.cycles,
      repoRoot,
      runDirectory,
      buildTarget: options.buildTarget,
      buildMode: options.buildMode,
    );
    final artifactPaths = artifactPathsFor(command, runDirectory);
    if (options.dryRun) {
      writeRunPlan(
        command: command,
        reportPath: options.reportPath,
        repoRoot: repoRoot,
        runDirectory: runDirectory,
        steps: steps,
        artifactPaths: artifactPaths,
      );
      return;
    }

    exitCode = await runDevCommand(
      command: command,
      format: options.format,
      reportPath: options.reportPath,
      repoRoot: repoRoot,
      runDirectory: runDirectory,
      steps: steps,
      artifactPaths: artifactPaths,
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _writeUsage();
    exitCode = 2;
  } catch (error) {
    stderr.writeln('Mozais tool failed: $error');
    exitCode = 1;
  }
}

void _writeUsage([String? command]) {
  if (command == null) {
    stdout.writeln('''Usage: fvm dart run tool/mozais.dart <command> [options]

Commands:
  build           Discover themes, generate sources, and build the Flutter app.
  verify          Run the full backend, Dart, Flutter, and D-Bus verification.
  verify-perf     Run the Linux profile performance gate.
  generate-scenes Generate generated theme scene code.
  trace-perf      Capture and summarize a Flutter performance timeline.

Options:
  --format text|json  Select console output format (default: text).
  --report PATH       Write the JSON run report to PATH.
  --cycles COUNT      Measurement cycles for verify-perf (minimum: 3).
  --platform NAME     Flutter build target for build (default: linux).
  --mode MODE         Flutter build mode: debug, profile, or release.
  --dry-run           Print the resolved execution plan as JSON.
  -h, --help          Show command help.''');
    return;
  }

  stdout.writeln('Usage: fvm dart run tool/mozais.dart $command [options]');
  if (command == 'build') {
    stdout.writeln(
      'Options: --platform NAME, --mode debug|profile|release, --format text|json, --report PATH, --dry-run.',
    );
  } else if (command == 'verify-perf') {
    stdout.writeln(
      'Options: --format text|json, --report PATH, --cycles COUNT (minimum: 3), --dry-run.',
    );
  } else {
    stdout.writeln('Options: --format text|json, --report PATH, --dry-run.');
  }
}

_CliOptions _parseOptions(String command, List<String> arguments) {
  var format = RunOutputFormat.text;
  var cycles = _minimumPerfCycles;
  var buildTarget = 'linux';
  String? buildMode;
  String? reportPath;
  var dryRun = false;
  var formatSeen = false;
  var cyclesSeen = false;
  var reportSeen = false;
  var dryRunSeen = false;
  var buildTargetSeen = false;
  var buildModeSeen = false;

  for (var index = 0; index < arguments.length; index++) {
    final option = arguments[index];
    if (option == '--dry-run') {
      if (dryRunSeen) {
        throw const FormatException('Duplicate --dry-run option.');
      }
      dryRunSeen = true;
      dryRun = true;
      continue;
    }
    if (!const {
      '--format',
      '--report',
      '--cycles',
      '--platform',
      '--mode',
    }.contains(option)) {
      throw FormatException('Unknown option: $option');
    }
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      throw FormatException('Missing value for $option.');
    }
    final value = arguments[++index];
    switch (option) {
      case '--format':
        if (formatSeen) {
          throw const FormatException('Duplicate --format option.');
        }
        formatSeen = true;
        format = switch (value) {
          'text' => RunOutputFormat.text,
          'json' => RunOutputFormat.json,
          _ => throw FormatException('Unknown output format: $value'),
        };
      case '--report':
        if (reportSeen) {
          throw const FormatException('Duplicate --report option.');
        }
        reportSeen = true;
        reportPath = value;
      case '--cycles':
        if (command != 'verify-perf') {
          throw const FormatException(
            '--cycles is only valid for verify-perf.',
          );
        }
        if (cyclesSeen) {
          throw const FormatException('Duplicate --cycles option.');
        }
        cyclesSeen = true;
        final parsedCycles = int.tryParse(value);
        if (parsedCycles == null || parsedCycles < _minimumPerfCycles) {
          throw FormatException(
            '--cycles must be an integer of at least $_minimumPerfCycles.',
          );
        }
        cycles = parsedCycles;
      case '--platform':
        if (command != 'build') {
          throw const FormatException('--platform is only valid for build.');
        }
        if (buildTargetSeen) {
          throw const FormatException('Duplicate --platform option.');
        }
        buildTargetSeen = true;
        if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(value)) {
          throw FormatException('Invalid Flutter build target: $value');
        }
        buildTarget = value;
      case '--mode':
        if (command != 'build') {
          throw const FormatException('--mode is only valid for build.');
        }
        if (buildModeSeen) {
          throw const FormatException('Duplicate --mode option.');
        }
        buildModeSeen = true;
        if (!const {'debug', 'profile', 'release'}.contains(value)) {
          throw FormatException('Unknown Flutter build mode: $value');
        }
        buildMode = value;
      default:
        throw FormatException('Unknown option: $option');
    }
  }

  return _CliOptions(
    format: format,
    cycles: cycles,
    buildTarget: buildTarget,
    buildMode: buildMode,
    reportPath: reportPath,
    dryRun: dryRun,
  );
}

Future<String> _createRunDirectory(
  Directory repoRoot, {
  required bool reserve,
}) async {
  final parentPath = _join(repoRoot.path, 'build/tool/runs');
  if (reserve) {
    await Directory(parentPath).create(recursive: true);
  }

  final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  var collision = 0;
  while (true) {
    final runId = collision == 0
        ? '$timestamp-$pid'
        : '$timestamp-$pid-$collision';
    final runDirectory = 'build/tool/runs/$runId';
    final directory = Directory(_join(repoRoot.path, runDirectory));
    if (directory.existsSync()) {
      collision++;
      continue;
    }
    if (!reserve) {
      return runDirectory;
    }

    try {
      await directory.create();
      return runDirectory;
    } on FileSystemException {
      if (!directory.existsSync()) {
        rethrow;
      }
      collision++;
    }
  }
}

Directory _findRepoRoot() {
  var directory = File.fromUri(Platform.script).parent.absolute;
  while (true) {
    final hasRootManifest = File(_join(directory.path, 'pubspec.yaml'))
        .existsSync();
    final hasBackendManifest = File(_join(directory.path, 'backend/Cargo.toml'))
        .existsSync();
    if (hasRootManifest && hasBackendManifest) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate the Mozais repository root.');
    }
    directory = parent;
  }
}

String _join(String base, String relative) {
  return '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
}

class _CliOptions {
  const _CliOptions({
    required this.format,
    required this.cycles,
    required this.buildTarget,
    required this.buildMode,
    required this.reportPath,
    required this.dryRun,
  });

  final RunOutputFormat format;
  final int cycles;
  final String buildTarget;
  final String? buildMode;
  final String? reportPath;
  final bool dryRun;
}
