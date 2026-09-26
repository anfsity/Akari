import 'dart:io';

import 'src/theme_catalog.dart';

void main(List<String> arguments) {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--write')) {
    stderr.writeln('Usage: dart run tool/theme_catalog.dart [--write]');
    exitCode = 2;
    return;
  }

  final repoRoot = Directory.current;
  final themes = findThemePackages(repoRoot);
  writeThemeCatalog(repoRoot: repoRoot, themes: themes);
  stdout.writeln(
    'Discovered ${themes.length} themes: ${themes.map((theme) => theme.themeName).join(', ')}',
  );
}
