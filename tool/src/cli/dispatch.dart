import 'dart:io';

import 'arguments.dart';
import 'definition.dart';
import 'installation.dart';
import 'usage.dart';
import 'completion.dart';
import '../commands/development.dart';
import '../commands/greetd_test.dart';
import '../commands/login.dart';
import '../execution/paths.dart';

Future<int> runCliCommand(CliCommand command, CliArguments input) async {
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
    case 'clean':
    case 'login enable':
    case 'login disable':
    case 'login rollback':
    case 'login configure-keyring':
    case 'login enable-gaze':
    case 'login disable-gaze':
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
      return runDevelopmentCommand(
        DevCommandOptions.parse(command, input),
        repoRoot,
      );
  }
}

Directory _findRepoRoot() {
  var directory = File.fromUri(Platform.script).parent.absolute;
  while (true) {
    final hasRootManifest = File(getJoinedPath(directory.path, 'pubspec.yaml'))
        .existsSync();
    final hasBackendManifest = File(
      getJoinedPath(directory.path, 'backend/Cargo.toml'),
    ).existsSync();
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
