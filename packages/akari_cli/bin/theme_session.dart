import 'dart:io';

import 'package:akari_cli/src/execution/paths.dart';
import 'package:akari_cli/src/theme/model.dart';
import 'package:akari_cli/src/theme/session.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: dart packages/akari_cli/bin/theme_session.dart THEME HOST MODE demo|real',
    );
    exitCode = 2;
    return;
  }
  exitCode = await ThemeSession(
    repoRoot: findRepositoryRoot(),
    theme: Directory(arguments[0]),
    host: Directory(arguments[1]),
    mode: BuildMode.values.byName(arguments[2]),
    backend: arguments[3],
  ).start();
}
