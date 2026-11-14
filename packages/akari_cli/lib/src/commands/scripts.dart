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
  final Map<String, String> values;
  if (command.scriptPath case final script?) {
    values = getCliOptionValues(command, input.options);
    path = script;
    arguments = input.theme;
  } else {
    final positional = <String>[];
    final optionArguments = <String>[];
    for (final argument in input.options) {
      if (argument.startsWith('-')) {
        optionArguments.add(argument);
      } else {
        positional.add(argument);
      }
    }
    values = getCliOptionValues(command, optionArguments);
    if (positional.length != 1) {
      throw const FormatException(
        'Usage: akari script run [--dry-run] SCRIPT -- [arguments]',
      );
    }
    path = positional.single;
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
  if (values.containsKey('--dry-run')) {
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
