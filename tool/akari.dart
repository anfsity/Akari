import 'dart:io';

import 'src/cli/arguments.dart';
import 'src/cli/definition.dart';
import 'src/cli/dispatch.dart';
import 'src/cli/usage.dart';
import 'src/theme/display_profile.dart';

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
    exitCode = await runCliCommand(command, input);
  } on DisplayProfileFailure catch (error) {
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
