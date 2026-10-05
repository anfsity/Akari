import 'dart:io';

import 'shell_completion.dart';

Future<void> installCli({
  required Directory repoRoot,
  required Directory prefix,
  required File rcFile,
  required String shell,
}) async {
  final launcher = File('${prefix.path}/bin/akari');
  const marker = '# Akari CLI launcher';
  if (await launcher.exists() &&
      !(await launcher.readAsString()).contains(marker)) {
    throw FileSystemException(
      'Installation would replace an unrelated command',
      launcher.path,
    );
  }
  final support = Directory('${prefix.path}/share/akari');
  await support.create(recursive: true);
  await launcher.parent.create(recursive: true);
  await launcher.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
$marker
repo_root=${encodeShellArgument(repoRoot.path)}
source "\$repo_root/scripts/lib.sh"
akari_run_dev_cli "\$repo_root" "\$@"
''');
  final chmod = await Process.run('chmod', ['+x', launcher.path]);
  if (chmod.exitCode != 0) {
    throw FileSystemException(
      'Cannot make launcher executable: ${chmod.stderr}',
      launcher.path,
    );
  }
  final completion = File('${support.path}/completion.$shell');
  await completion.writeAsString(getShellCompletion(shell));
  final environment = File('${support.path}/env.$shell');
  await environment.writeAsString('''# Akari CLI environment
case ":\$PATH:" in
  *:${encodeShellArgument(launcher.parent.path)}:*) ;;
  *) export PATH=${encodeShellArgument(launcher.parent.path)}:"\$PATH" ;;
esac
${shell == 'zsh' ? 'if (( ! \$+functions[compdef] )); then\n  autoload -Uz compinit\n  compinit\nfi\n' : ''}. ${encodeShellArgument(completion.path)}
''');
  await rcFile.parent.create(recursive: true);
  final startup = await rcFile.exists() ? await rcFile.readAsString() : '';
  final registration =
      'if [ -f ${encodeShellArgument(environment.path)} ]; then . ${encodeShellArgument(environment.path)}; fi';
  if (!startup.split('\n').contains(registration)) {
    await rcFile.writeAsString(
      '\n# Akari CLI\n$registration\n',
      mode: FileMode.append,
    );
  }
  stdout.writeln('Installed command: ${launcher.path}');
  stdout.writeln('Registered $shell completion in ${rcFile.path}');
  stdout.writeln(
    'Open a new shell or run: . ${encodeShellArgument(environment.path)}',
  );
}
