import 'src/theme/model.dart';

import 'dart:io';

import 'src/theme/project.dart';
import 'src/theme/host.dart';

void main(List<String> arguments) {
  if (arguments.length < 2 ||
      arguments.length > 3 ||
      (arguments.length == 3 &&
          !const {'--preview', '--studio'}.contains(arguments.last))) {
    stderr.writeln(
      'Usage: dart tool/theme_host.dart THEME OUTPUT [--preview|--studio]',
    );
    exitCode = 2;
    return;
  }
  createThemeHost(
    repoRoot: File.fromUri(Platform.script).parent.parent,
    theme: getThemePackage(Directory(arguments[0])),
    output: Directory(arguments[1]),
    kind: switch (arguments.last) {
      '--studio' => ThemeHostKind.studio,
      '--preview' => ThemeHostKind.preview,
      _ => ThemeHostKind.greeter,
    },
  );
}
