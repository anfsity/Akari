import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene_editor/src/editor_controller.dart';
import 'package:mozais_scene_editor/src/editor_strings.dart';
import 'package:mozais_scene_editor/src/english_strings.dart';
import 'package:mozais_scene_editor/src/inspector_panel.dart';

const _scene = '''
{
  "id": "test",
  "version": 1,
  "canvas": {"fit": "cover"},
  "background": {"kind": "solid"},
  "nodes": [
    {
      "id": "panel",
      "kind": "glassPanel",
      "rect": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2}
    }
  ]
}
''';

void main() {
  late Directory directory;
  late SceneEditorController controller;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('mozais_inspector');
    final file = File('${directory.path}/test.scene.json')
      ..writeAsStringSync(_scene);
    controller = SceneEditorController()..setPath(file.path);
    await controller.open();
  });

  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      EditorStringsScope(
        strings: const EnglishStrings(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 600,
              child: InspectorPanel(controller: controller),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('opens on the document tab', (tester) async {
    await pump(tester);

    expect(find.text('Document'), findsOneWidget);
    expect(find.text('Canvas'), findsOneWidget);
  });

  testWidgets('switches to the node identity tab', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Identity'));
    await tester.pumpAndSettle();

    expect(find.text('kind'), findsOneWidget);
  });

  testWidgets('applies exact pixel positions from the layout tab', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Layout'));
    await tester.pumpAndSettle();

    final xField = find.byKey(const ValueKey('panel.x:192.0'));
    await tester.enterText(xField, '384');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(controller.selectedNode!.rect.x, closeTo(0.2, 0.0001));
  });

  testWidgets('scrolls the tab strip with the wheel', (tester) async {
    await pump(tester);
    final position = _tabScrollPosition(tester);
    final before = position.pixels;

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(TabBar)),
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump();

    expect(position.pixels, greaterThan(before));
  });

  testWidgets('scrolls the tab strip with a middle-button drag', (
    tester,
  ) async {
    await pump(tester);
    final position = _tabScrollPosition(tester);
    final before = position.pixels;

    await tester.dragFrom(
      tester.getCenter(find.byType(TabBar)),
      const Offset(-80, 0),
      buttons: kMiddleMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(position.pixels, greaterThan(before));
  });
}

ScrollPosition _tabScrollPosition(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byType(TabBar),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollable).position;
}
