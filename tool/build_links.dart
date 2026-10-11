import 'src/theme/model.dart';

import 'dart:io';

import 'src/theme/build_links.dart';
import 'src/theme/project.dart';

Future<void> main(List<String> arguments) async {
  await updateBuildLinks(
    Directory(arguments[0]),
    getThemePackage(Directory(arguments[1])),
    BuildMode.values.byName(arguments[2]),
  );
}
