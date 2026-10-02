import 'dart:io';

import 'src/build_links.dart';
import 'src/theme_project.dart';

Future<void> main(List<String> arguments) async {
  await updateBuildLinks(
    Directory(arguments[0]),
    getThemePackage(Directory(arguments[1])),
    arguments[2],
  );
}
