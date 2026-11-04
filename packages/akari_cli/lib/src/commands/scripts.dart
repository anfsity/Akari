import 'dart:convert';
import 'dart:io';

import '../cli/arguments.dart';
import '../cli/definition.dart';
import '../cli/scripts.dart';

Future<int> runScriptCommand(
  CliCommand command,
  CliArguments input,
  Directory repoRoot,
) async {
  if (input.forwardsArguments && !command.forwardsArguments) {
    throw FormatException('${command.name} does not accept arguments after --.');
  }
  if (command.name == 'script list') {
    final values = getCliOptionValues(command, input.raw);
    final scripts = findRepositoryScripts(repoRoot);
    if (values['--format'] == 'json') {
      stdout.writeln(
        jsonEncode([
          for (final script in scripts)
            {
              'path': script.path,
              'kind': script.kind.name,
              'description': script.description,
            },
        ]),
      );
    } else {
      for (final script in scripts) {
        stdout.writeln(
          '${script.path.padRight(36)} ${script.kind.name.padRight(8)} ${script.description}',
        );
      }
    }
    return 0;
  }
  final String path;
  final List<String> arguments;
  if (command.scriptPath case final script?) {
    getCliOptionValues(command, input.options);
    path = script;
    arguments = input.theme;
  } else {
    if (input.options.isEmpty || input.options.first.startsWith('-')) {
      throw const FormatException(
        'Usage: akari script run SCRIPT [--dry-run] -- [arguments]',
      );
    }
    path = input.options.first;
    getCliOptionValues(command, input.options.skip(1).toList());
    arguments = input.theme;
  }
  final script = getRepositoryScript(path);
  if (script.kind == ScriptKind.library) {
    throw FormatException('${script.path} is a library: ${script.description}');
  }
  final invocation = [
    script.interpreter,
    '${repoRoot.path}/scripts/${script.path}',
    ...arguments,
  ];
  if (input.options.contains('--dry-run')) {
    stdout.writeln(
      jsonEncode({
        'command': command.name,
        'invocation': invocation,
        'working_directory': repoRoot.path,
      }),
    );
    return 0;
  }
  if (script.kind == ScriptKind.internal) stderr.writeln(script.description);
  final process = await Process.start(
    invocation.first,
    invocation.skip(1).toList(),
    workingDirectory: repoRoot.path,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}
