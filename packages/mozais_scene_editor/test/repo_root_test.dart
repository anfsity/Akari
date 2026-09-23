import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene_editor/src/repo_root.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('mozais_repo_root');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('resolves the bundled default scene from the repository root', () {
    expect(
      defaultScenePath(),
      endsWith(
        'packages/mozais_greeter_ui/lib/themes/default/default.scene.json',
      ),
    );
  });

  test('keeps a configured path while it exists', () {
    final file = File('${directory.path}/scene.json')
      ..writeAsStringSync('{}');

    expect(resolveStartupScenePath(file.path), file.path);
  });

  test('falls back when the configured path is missing', () {
    final path = resolveStartupScenePath('${directory.path}/missing.json');

    expect(path, isNot('${directory.path}/missing.json'));
    expect(path, isNotEmpty);
  });
}
