import 'dart:io';

import 'src/command_plans.dart';
import 'src/run_report.dart';
import 'src/theme_project.dart';

const _commands = {
  'build',
  'run',
  'preview',
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
    final selectedTheme =
        (options.themePath != null ||
            const {'build', 'run', 'preview'}.contains(command))
        ? getThemePackage(
            Directory(
              options.themePath ?? _join(repoRoot.path, 'themes/default'),
            ),
          )
        : null;
    final preview = command == 'preview';
    final buildMode =
        options.buildMode ?? (command == 'build' ? 'release' : 'debug');
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
      buildMode: buildMode,
      selectedTheme: selectedTheme,
      preview: preview,
      jobs: options.jobs,
      backendMode: options.backendMode,
    );
    final artifactPaths = artifactPathsFor(
      command,
      runDirectory,
      buildTarget: options.buildTarget,
      buildMode: buildMode,
      selectedTheme: selectedTheme,
      preview: preview,
      backendMode: command == 'run' ? options.backendMode : 'real',
    );
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

    final themes = selectedTheme == null
        ? findThemePackages(repoRoot)
        : [selectedTheme];
    final locks = <RandomAccessFile>[];
    try {
      // Theme generation writes into the source package, so serialize all
      // commands for that theme, including live previews with a watcher.
      for (final theme in themes) {
        final file = File(
          _join(
            repoRoot.path,
            'build/tool/locks/${getThemeCacheKey(theme)}/theme.lock',
          ),
        );
        await file.parent.create(recursive: true);
        final lock = await file.open(mode: FileMode.append);
        locks.add(lock);
        await lock.lock(FileLock.blockingExclusive);
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
    } finally {
      for (final lock in locks.reversed) {
        await lock.close();
      }
    }
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
  stdout.writeln(
    'Usage: fvm dart run tool/mozais.dart ${command ?? '<command>'} [options]',
  );
  stdout.writeln('''
Commands:
  build           Build the selected frontend and production Rust backend.
  run             Run the selected greeter and backend on a private D-Bus session.
  preview         Run the selected theme with demo login state.
  verify          Verify shared code, backend, and theme projects.
  verify-perf     Execute the selected theme's performance gate.
  generate-scenes Generate theme scene code.
  trace-perf      Execute the selected theme's performance trace.

Options:
  --theme PATH        Select a theme project (default: themes/default).
  --backend mock|real Backend transport for run (default: mock).
  --jobs COUNT        Limit Cargo and native compile/link parallel jobs.
  --platform NAME     Flutter target for build (default: linux).
  --mode MODE         debug, profile, or release (build: release; run/preview: debug).
  --cycles COUNT      Performance cycles for verify-perf (minimum: 3).
  --format text|json  Console output format (default: text).
  --report PATH       Write the run report to PATH.
  --dry-run           Print the execution plan without changing files.
  -h, --help          Show help.''');
}

_CliOptions _parseOptions(String command, List<String> arguments) {
  final values = <String, String>{};
  var dryRun = false;
  final specific = switch (command) {
    'build' => {'--theme', '--jobs', '--mode', '--platform'},
    'run' => {'--theme', '--jobs', '--mode', '--backend'},
    'preview' => {'--theme', '--jobs', '--mode'},
    'verify-perf' => {'--cycles'},
    'verify' || 'generate-scenes' => {'--theme'},
    _ => <String>{},
  };
  final allowed = {'--format', '--report', ...specific};
  for (var index = 0; index < arguments.length; index++) {
    final option = arguments[index];
    if (option == '--dry-run') {
      if (dryRun) {
        throw const FormatException('Duplicate --dry-run option.');
      }
      dryRun = true;
      continue;
    }
    if (!allowed.contains(option)) {
      throw FormatException('Unknown option for $command: $option');
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
  final format = switch (values['--format'] ?? 'text') {
    'text' => RunOutputFormat.text,
    'json' => RunOutputFormat.json,
    final value => throw FormatException('Unknown output format: $value'),
  };
  final jobs = values.containsKey('--jobs')
      ? int.tryParse(values['--jobs']!)
      : null;
  if (values.containsKey('--jobs') && (jobs == null || jobs < 1)) {
    throw const FormatException('--jobs must be a positive integer.');
  }
  final mode = values['--mode'];
  if (mode != null && !const {'debug', 'profile', 'release'}.contains(mode)) {
    throw FormatException('Unknown Flutter build mode: $mode');
  }
  final target = values['--platform'] ?? 'linux';
  if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(target)) {
    throw FormatException('Invalid Flutter build target: $target');
  }
  final backend = values['--backend'] ?? 'mock';
  if (!const {'mock', 'real'}.contains(backend)) {
    throw FormatException('Unknown backend transport: $backend');
  }
  final cycles = values.containsKey('--cycles')
      ? int.tryParse(values['--cycles']!)
      : _minimumPerfCycles;
  if (cycles == null || cycles < _minimumPerfCycles) {
    throw const FormatException('--cycles must be an integer of at least 3.');
  }
  return _CliOptions(
    format: format,
    cycles: cycles,
    buildTarget: target,
    buildMode: mode,
    themePath: values['--theme'],
    reportPath: values['--report'],
    dryRun: dryRun,
    jobs: jobs,
    backendMode: backend,
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
    required this.themePath,
    required this.jobs,
    required this.backendMode,
  });
  final RunOutputFormat format;
  final int cycles;
  final String buildTarget;
  final String? buildMode;
  final String? reportPath;
  final bool dryRun;
  final String? themePath;
  final int? jobs;
  final String backendMode;
}
