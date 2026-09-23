import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene_editor/src/editor_strings.dart';
import 'package:mozais_scene_editor/src/english_strings.dart';
import 'package:mozais_scene_editor/src/file_picker_dialog.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('mozais_file_picker');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  testWidgets('navigates directories and returns the chosen file', (
    tester,
  ) async {
    final nested = Directory('${directory.path}/wallpapers')..createSync();
    final file = File('${nested.path}/photo.png')..writeAsStringSync('x');

    File? picked;
    await tester.pumpWidget(
      EditorStringsScope(
        strings: const EnglishStrings(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await pickFile(
                      context,
                      initialDirectory: directory,
                    );
                  },
                  child: const Text('pick'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('wallpapers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('photo.png'));
    await tester.pumpAndSettle();

    expect(picked?.path, file.path);
  });
}
