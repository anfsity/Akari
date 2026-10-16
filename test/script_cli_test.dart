import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/cli/definition.dart';
import '../tool/src/cli/scripts.dart';
import '../tool/src/sdk_commands.dart';

void main() {
  test('every script is classified and bound commands reference a tool', () {
    final scripts = findRepositoryScripts(Directory.current);
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
import '${Directory.current.uri}tool/src/cli/arguments.dart';
import '${Directory.current.uri}tool/src/cli/definition.dart';
import '${Directory.current.uri}tool/src/commands/scripts.dart';
Future<void> main(List<String> arguments) async {
  final (command, remaining) = getCliInvocation(arguments);
  exitCode = await runScriptCommand(command, CliArguments(remaining), Directory.current);
}
''');
      final dart = getDartCommand(Directory.current);
      const arguments = ['--help', r'$(touch unexpected)', 'path with spaces'];
      for (final command in [
        ['script', 'run', 'verify-docs.py'],
        ['docs', 'verify'],
      ]) {
        final result = await Process.run(dart.first, [
          ...dart.skip(1),
          runner.path,
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
    final dart = getDartCommand(Directory.current);
    Future<ProcessResult> run(List<String> arguments) =>
        Process.run(dart.first, [
          ...dart.skip(1),
          '${Directory.current.path}/tool/akari.dart',
          ...arguments,
        ], workingDirectory: Directory.systemTemp.path);
    final inventory = await run(['script', 'list', '--format', 'json']);
    expect(inventory.exitCode, 0, reason: '${inventory.stderr}');
    expect(
      jsonDecode(inventory.stdout as String),
      hasLength(repositoryScripts.length),
    );
    final plan = await run([
      'script',
      'run',
      'greetd-test/display-layout.py',
      '--dry-run',
      '--',
      'capture',
    ]);
    expect(plan.exitCode, 0, reason: '${plan.stderr}');
    expect((jsonDecode(plan.stdout as String) as Map)['invocation'], [
      'python3',
      '${Directory.current.path}/scripts/greetd-test/display-layout.py',
      'capture',
    ]);
    for (final path in ['../outside.sh', 'lib.sh', 'unknown.sh']) {
      expect((await run(['script', 'run', path, '--dry-run'])).exitCode, 2);
    }
  });
}
