import 'dart:io';

import 'package:akari_cli/src/cli/arguments.dart';
import 'package:akari_cli/src/cli/definition.dart';
import 'package:akari_cli/src/cli/dispatch.dart';
import 'package:akari_cli/src/cli/usage.dart';
import 'package:akari_cli/src/theme/display_profile.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty || const {'-h', '--help'}.contains(arguments.first)) {
      writeCliUsage();
      return;
    }
    final (command, remaining) = getCliInvocation(arguments);
    final input = CliArguments(remaining);
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
