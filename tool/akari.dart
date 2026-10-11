import 'dart:convert';
import 'dart:io';

import 'src/cli_arguments.dart';
import 'src/cli_definition.dart';
import 'src/cli_install.dart';
import 'src/cli_usage.dart';
import 'src/command_plans.dart';
import 'src/greetd_test.dart';
import 'src/login.dart';
import 'src/execution/report.dart';
import 'src/commands/development.dart';
import 'src/shell_completion.dart';
import 'src/theme_project.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty || const {'-h', '--help'}.contains(arguments.first)) {
      writeCliUsage();
      return;
    }
    final commandWords = arguments
        .takeWhile((argument) => !argument.startsWith('-'))
        .toList();
    final command = getCliCommand(commandWords.join(' '));
    final input = CliArguments(arguments.skip(commandWords.length).toList());
    if (input.hasHelp) {
      writeCliUsage(command);
      return;
    }
    exitCode = await _runCommand(command, input);
  } on _DisplayProfileFailure catch (error) {
    exitCode = error.exitCode;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    writeCliUsage();
    exitCode = 2;
  } catch (error) {
    stderr.writeln('Akari tool failed: $error');
    exitCode = 1;
  }
}

Future<int> _runCommand(CliCommand command, CliArguments input) async {
  // Installed service commands retain their own argument boundary; they can
  // run without preparing a theme, a run directory, or development reports.
  final arguments = input.raw;
  switch (command.name) {
    case 'greetd-test':
    case 'login':
      getCliOptionValues(command, arguments);
      writeCliUsage(command);
      return 0;
    case 'install':
    case 'uninstall':
    case 'login enable':
    case 'login disable':
    case 'login rollback':
    case 'login status':
    case 'login logs':
      return runLoginCommand(command, arguments, repoRoot: _findRepoRoot());
    case 'greetd-test install':
    case 'greetd-test start':
    case 'greetd-test restore':
    case 'greetd-test status':
    case 'greetd-test logs':
      return runGreetdTestCommand(
        command,
        arguments,
        repoRoot: command.name == 'greetd-test install'
            ? _findRepoRoot()
            : null,
      );
    case 'completion':
      final values = getCliOptionValues(command, arguments);
      stdout.write(getShellCompletion(values['--shell'] ?? 'zsh'));
      return 0;
    case 'install cli':
      final repoRoot = _findRepoRoot();
      final values = getCliOptionValues(command, arguments);
      final shell = values['--shell'] ?? 'zsh';
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
      return 0;
    default:
      final repoRoot = _findRepoRoot();
      return _runThemeCommand(
        command.name,
        DevCommandOptions.parse(command, input),
        repoRoot,
      );
  }
}

Future<int> _runThemeCommand(
  String command,
  DevCommandOptions options,
  Directory repoRoot,
) async {
  final selectedTheme =
      (options.themePath != null ||
          const {
            'build',
            'run',
            'run sway',
            'preview',
            'run studio',
            'verify-perf',
            'trace-perf',
          }.contains(command))
      ? getThemePackage(
          Directory(
            options.themePath ?? _join(repoRoot.path, 'themes/default'),
          ),
        )
      : null;
  final preview = command == 'preview' || command == 'run studio';
  final buildMode =
      options.buildMode ?? (command == 'build' ? 'release' : 'debug');
  final displayProfile = command == 'run sway'
      ? await _resolveDisplayProfile(repoRoot, options)
      : null;
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
    displayProfile: displayProfile,
    swayBackend: options.swayBackend,
  );
  final artifactPaths = artifactPathsFor(
    command,
    runDirectory,
    buildTarget: options.buildTarget,
    buildMode: buildMode,
    selectedTheme: selectedTheme,
    preview: preview,
    backendMode: command == 'run' || command == 'run sway'
        ? options.backendMode
        : 'real',
  );
  if (options.dryRun) {
    RunReport(
      command: command,
      reportPath: options.reportPath,
      repoRoot: repoRoot,
      runDirectory: runDirectory,
      steps: steps,
      artifactPaths: artifactPaths,
      displayProfile: displayProfile,
      format: options.format,
    ).writePlan();
    return 0;
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
    return await runDevCommand(
      command: command,
      format: options.format,
      reportPath: options.reportPath,
      repoRoot: repoRoot,
      runDirectory: runDirectory,
      steps: steps,
      artifactPaths: artifactPaths,
      displayProfile: displayProfile,
    );
  } finally {
    for (final lock in locks.reversed) {
      await lock.close();
    }
  }
}

Future<Map<String, Object?>> _resolveDisplayProfile(
  Directory repoRoot,
  DevCommandOptions options,
) async {
  final stateHome = Platform.environment['XDG_STATE_HOME'];
  final String state;
  if (stateHome != null && stateHome.isNotEmpty) {
    state = stateHome;
  } else {
    final home = Platform.environment['HOME'];
    if (home == null) {
      throw const FormatException('HOME or XDG_STATE_HOME is required.');
    }
    state = '$home/.local/state';
  }
  final result = await Process.run('python3', [
    _join(repoRoot.path, 'scripts/greetd-test/display_profile.py'),
    '--reference',
    _join(repoRoot.path, 'config/sway/reference.json'),
    '--state',
    '$state/akari/display-profiles',
    '--display-profile',
    options.displayProfile,
    if (options.resolution != null) ...['--resolution', options.resolution!],
    if (options.scale != null) ...['--scale', options.scale!],
    if (options.dryRun) '--dry-run',
  ]);
  if ((result.stderr as String).isNotEmpty) stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw _DisplayProfileFailure(result.exitCode);
  }
  return (jsonDecode(result.stdout as String) as Map).cast<String, Object?>();
}

class _DisplayProfileFailure implements Exception {
  const _DisplayProfileFailure(this.exitCode);
  final int exitCode;
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
      throw StateError('Could not locate the Akari repository root.');
    }
    directory = parent;
  }
}

String _join(String base, String relative) {
  return '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
}
