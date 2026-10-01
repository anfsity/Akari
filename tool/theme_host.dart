import 'dart:io';

import 'src/theme_catalog.dart';
import 'src/theme_host.dart';

void main(List<String> arguments) {
  if (arguments.length < 2 ||
      arguments.length > 3 ||
      (arguments.length == 3 && arguments.last != '--preview')) {
    stderr.writeln('Usage: dart tool/theme_host.dart THEME OUTPUT [--preview]');
    exitCode = 2;
    return;
  }
  createThemeHost(
    repoRoot: File.fromUri(Platform.script).parent.parent,
    theme: getThemePackage(Directory(arguments[0])),
    output: Directory(arguments[1]),
    preview: arguments.length == 3,
  );
}
