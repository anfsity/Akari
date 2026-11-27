import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:akari_cli/src/execution/paths.dart';

import 'package:akari_cli/src/cli/definition.dart';
import 'package:akari_cli/src/cli/scripts.dart';
import 'package:akari_cli/src/sdk_commands.dart';

import 'cli_test_snapshots.dart';

final _repoRoot = findRepositoryRoot();

void main() {
  late String akariSnapshot;
  setUpAll(() async {
    akariSnapshot = await ensureAkariCliSnapshot(_repoRoot);
  });

  test('every script is classified and bound commands reference a tool', () {
    final scripts = findRepositoryScripts(_repoRoot);
    expect(
      scripts.map((script) => script.path).toSet(),
      repositoryScripts.map((script) => script.path).toSet(),
    );
    for (final command in cliCommands.where(
      (command) => command.scriptPath != null,
    )) {
      expect(getRepositoryScript(command.scriptPath!).kind, ScriptKind.tool);
    }
  });

  test(
    'script execution preserves literal arguments, help and exit status',
    () async {
      final root = await Directory.systemTemp.createTemp('akari-script-');
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/scripts').create();
      await File('${root.path}/scripts/verify-docs.py').writeAsString('''
import json, sys
print(json.dumps(sys.argv[1:]))
sys.exit(7)
''');
      final runner = File('${root.path}/runner.dart');
      await runner.writeAsString('''
import 'dart:io';
import '${_repoRoot.uri}packages/akari_cli/lib/src/cli/arguments.dart';
import '${_repoRoot.uri}packages/akari_cli/lib/src/cli/definition.dart';
import '${_repoRoot.uri}packages/akari_cli/lib/src/commands/scripts.dart';
Future<void> main(List<String> arguments) async {
  final (command, remaining) = getCliInvocation(arguments);
  exitCode = await runScriptCommand(command, CliArguments(remaining), Directory.current);
}
''');
      final runnerSnapshot = await compileDartKernelSnapshot(
        _repoRoot,
        source: runner,
        output: File('${root.path}/runner.dill'),
      );
      final dart = getDartCommand(_repoRoot);
      const arguments = ['--help', r'$(touch unexpected)', 'path with spaces'];
      for (final command in [
        ['script', 'run', 'verify-docs.py'],
        ['docs', 'verify'],
      ]) {
        final result = await Process.run(dart.first, [
          ...dart.skip(1),
          runnerSnapshot,
          ...command,
          '--',
          ...arguments,
        ], workingDirectory: root.path);
        expect(result.exitCode, 7, reason: '${result.stderr}');
        expect(jsonDecode(result.stdout as String), arguments);
        expect(File('${root.path}/unexpected').existsSync(), isFalse);
      }
    },
  );

  test('script discovery and dry runs work outside the repository', () async {
    final dart = getDartCommand(_repoRoot);
    Future<ProcessResult> run(List<String> arguments) => Process.run(
      dart.first,
      [...dart.skip(1), akariSnapshot, ...arguments],
      workingDirectory: Directory.systemTemp.path,
    );
    final inventory = await run(['script', 'list', '--format', 'json']);
    expect(inventory.exitCode, 0, reason: '${inventory.stderr}');
    expect(
      jsonDecode(inventory.stdout as String),
      hasLength(repositoryScripts.length),
    );
    final plan = await run([
      'script',
      'run',
      '--dry-run',
      'greetd-test/display-layout.py',
      '--',
      'capture',
    ]);
    expect(plan.exitCode, 0, reason: '${plan.stderr}');
    expect((jsonDecode(plan.stdout as String) as Map)['invocation'], [
      'python3',
      '${_repoRoot.path}/scripts/greetd-test/display-layout.py',
      'capture',
    ]);
    final suffixDryRun = await run([
      'script',
      'run',
      'greetd-test/display-layout.py',
      '--dry-run',
      '--',
      'capture',
    ]);
    expect(suffixDryRun.exitCode, 0, reason: '${suffixDryRun.stderr}');
    expect((jsonDecode(suffixDryRun.stdout as String) as Map)['invocation'], [
      'python3',
      '${_repoRoot.path}/scripts/greetd-test/display-layout.py',
      'capture',
    ]);
    for (final path in ['../outside.sh', 'lib.sh', 'unknown.sh']) {
      expect((await run(['script', 'run', path, '--dry-run'])).exitCode, 2);
    }
  });
}
