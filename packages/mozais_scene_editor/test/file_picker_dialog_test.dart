import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene_editor/src/editor_strings.dart';
import 'package:mozais_scene_editor/src/english_strings.dart';
import 'package:mozais_scene_editor/src/file_picker_dialog.dart';

void main() {
  late Directory directory;
  late File? picked;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('mozais_file_picker');
    picked = null;
  });

  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> pumpPicker(
    WidgetTester tester, {
    Set<String> extensions = const {},
  }) async {
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
                      extensions: extensions,
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
  }

  testWidgets('navigates directories and returns the chosen file', (
    tester,
  ) async {
    final nested = Directory('${directory.path}/wallpapers')..createSync();
    final file = File('${nested.path}/photo.png')..writeAsStringSync('x');

    await pumpPicker(tester);

    await tester.tap(find.text('wallpapers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('photo.png'));
    await tester.pumpAndSettle();

    expect(picked?.path, file.path);
  });

  testWidgets('filters the listed files by extension', (tester) async {
    File('${directory.path}/scene.json').writeAsStringSync('{}');
    File('${directory.path}/photo.png').writeAsStringSync('x');

    await pumpPicker(tester, extensions: const {'json'});

    expect(find.text('scene.json'), findsOneWidget);
    expect(find.text('photo.png'), findsNothing);
  });

  testWidgets('navigates to a typed path', (tester) async {
    final nested = Directory('${directory.path}/wallpapers')..createSync();
    File('${nested.path}/photo.png').writeAsStringSync('x');

    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), nested.path);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('photo.png'), findsOneWidget);
  });
}
