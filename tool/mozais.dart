import 'dart:io';

import 'src/cli_definition.dart';
import 'src/cli_install.dart';
import 'src/command_plans.dart';
import 'src/run_report.dart';
import 'src/shell_completion.dart';
import 'src/theme_project.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty || const {'-h', '--help'}.contains(arguments.first)) {
      _writeUsage();
      return;
    }

    final definition = getCliCommand(arguments.first);
    final command = definition.name;
    final separator = arguments.indexOf('--');
    final cliArguments = separator < 0 ? arguments : arguments.take(separator);
    if (cliArguments
        .skip(1)
        .any((argument) => argument == '-h' || argument == '--help')) {
      _writeUsage(definition);
      return;
    }

    final repoRoot = _findRepoRoot();
    if (command == 'install' || command == 'completion') {
      final values = getCliOptionValues(definition, arguments.skip(1).toList());
      final shell = values['--shell'] ?? 'zsh';
      if (command == 'completion') {
        stdout.write(getShellCompletion(shell));
        return;
      }
      final home = Platform.environment['HOME'];
      if (home == null) {
        throw const FormatException('HOME is required for installation.');
      }
      final rcDirectory = shell == 'zsh'
          ? Platform.environment['ZDOTDIR'] ?? home
          : home;
      await installCli(
        repoRoot: repoRoot,
        prefix: Directory(values['--prefix'] ?? '$home/.local').absolute,
        rcFile: File(values['--rc'] ?? '$rcDirectory/.${shell}rc').absolute,
        shell: shell,
      );
      return;
    }
    final options = _parseOptions(definition, arguments.skip(1).toList());
    final selectedTheme =
        (options.themePath != null ||
            const {
              'build',
              'run',
              'preview',
              'verify-perf',
              'trace-perf',
            }.contains(command))
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
      repoRoot,
      runDirectory,
      buildTarget: options.buildTarget,
      buildMode: buildMode,
      selectedTheme: selectedTheme,
      preview: preview,
      jobs: options.jobs,
      backendMode: options.backendMode,
      themeArguments: options.themeArguments,
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

void _writeUsage([CliCommand? command]) {
  stdout.writeln('Usage: mozais ${command?.name ?? '<command>'} [options]');
  if (command == null) {
    stdout.writeln('\nCommands:');
    for (final definition in cliCommands) {
      final names = definition.spellings.join(', ');
      stdout.writeln('  ${names.padRight(24)} ${definition.description}');
    }
  }
  stdout.writeln('\nOptions:');
  final options = command == null ? cliOptions.values : getCliOptions(command);
  for (final option in options) {
    final label =
        '${option.spellings.join(', ')}${option.valueName == null ? '' : ' ${option.valueName}'}';
    stdout.writeln('  ${label.padRight(24)} ${option.description}');
  }
  if (command == null || command.forwardsArguments) {
    stdout.writeln(
      '  -- [arguments]           Forward arguments to the theme perf command.',
    );
  }
}

_CliOptions _parseOptions(CliCommand command, List<String> arguments) {
  final separator = arguments.indexOf('--');
  final themeArguments = separator < 0
      ? <String>[]
      : arguments.sublist(separator + 1);
  if (separator >= 0 && !command.forwardsArguments) {
    throw FormatException(
      '${command.name} does not accept theme arguments after --.',
    );
  }
  final values = getCliOptionValues(
    command,
    separator < 0 ? arguments : arguments.sublist(0, separator),
  );
  final format = values['--format'] == 'json'
      ? RunOutputFormat.json
      : RunOutputFormat.text;
  final jobs = values.containsKey('--jobs')
      ? int.tryParse(values['--jobs']!)
      : null;
  if (values.containsKey('--jobs') && (jobs == null || jobs < 1)) {
    throw const FormatException('--jobs must be a positive integer.');
  }
  final target = values['--platform'] ?? 'linux';
  if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(target)) {
    throw FormatException('Invalid Flutter build target: $target');
  }
  return _CliOptions(
    format: format,
    themeArguments: themeArguments,
    buildTarget: target,
    buildMode: values['--mode'],
    themePath: values['--theme'],
    reportPath: values['--report'],
    dryRun: values.containsKey('--dry-run'),
    jobs: jobs,
    backendMode: values['--backend'] ?? 'mock',
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
    required this.themeArguments,
    required this.buildTarget,
    required this.buildMode,
    required this.reportPath,
    required this.dryRun,
    required this.themePath,
    required this.jobs,
    required this.backendMode,
  });
  final RunOutputFormat format;
  final List<String> themeArguments;
  final String buildTarget;
  final String? buildMode;
  final String? reportPath;
  final bool dryRun;
  final String? themePath;
  final int? jobs;
  final String backendMode;
}
