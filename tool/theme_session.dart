import 'dart:io';

import 'src/theme/model.dart';
import 'src/theme/session.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: dart tool/theme_session.dart THEME HOST MODE demo|real',
    );
    exitCode = 2;
    return;
  }
  exitCode = await ThemeSession(
    repoRoot: File.fromUri(Platform.script).parent.parent,
    theme: Directory(arguments[0]),
    host: Directory(arguments[1]),
    mode: BuildMode.values.byName(arguments[2]),
    backend: arguments[3],
  ).start();
}
