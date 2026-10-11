import 'dart:io';

import 'cli_definition.dart';

void writeCliUsage([CliCommand? command]) {
  final Iterable<CliOption> options;
  final bool forwardsArguments;
  if (command == null) {
    stdout.writeln('Usage: akari <command> [options]');
    stdout.writeln('\nCommands:');
    for (final definition in cliCommands) {
      stdout.writeln(
        '  ${definition.spellings.join(', ').padRight(24)} ${definition.description}',
      );
    }
    options = cliOptions.values;
    forwardsArguments = true;
  } else {
    final subcommands = getCliSubcommands(command.name);
    stdout.writeln(
      'Usage: akari ${command.name}${subcommands.isEmpty ? '' : ' [target]'} [options]',
    );
    stdout.writeln('\n${command.description}');
    if (subcommands.isNotEmpty) {
      stdout.writeln('\nTargets:');
      for (final subcommand in subcommands) {
        final target = subcommand.name.substring(command.name.length + 1);
        stdout.writeln('  ${target.padRight(24)} ${subcommand.description}');
      }
      stdout.writeln(
        '\nUse akari ${command.name} <target> --help for target options.',
      );
    }
    options = getCliOptions(command);
    forwardsArguments = command.forwardsArguments;
  }
  stdout.writeln('\nOptions:');
  for (final option in options) {
    final label =
        '${option.spellings.join(', ')}${option.valueName == null ? '' : ' ${option.valueName}'}';
    stdout.writeln('  ${label.padRight(24)} ${option.description}');
  }
  if (forwardsArguments) {
    stdout.writeln(
      '  -- [arguments]           Forward arguments to the theme perf command.',
    );
  }
}
