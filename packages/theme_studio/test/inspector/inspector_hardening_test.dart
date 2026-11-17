import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/authoring/scene_editor.dart';
import 'package:theme_studio/src/canvas/node_geometry.dart';
import 'package:theme_studio/src/inspector/code_inspector.dart';
import 'package:theme_studio/src/inspector/node_inspector.dart';
import 'package:theme_studio/src/inspector/node_layout_inspector.dart';

void main() {
  SceneEditor createEditor(Directory root, {double minHitTarget = 44}) {
    final sceneFile = File('${root.path}/scene.json')
      ..writeAsStringSync(
        encodeSceneDocument(
          const SceneDocument(
            id: 'test',
            version: currentSceneVersion,
            canvas: SceneCanvas(referenceWidth: 1280, referenceHeight: 720),
            background: SceneBackground(kind: SceneBackgroundKind.solid),
            nodes: [
              SceneNode(
                id: 'frame',
                componentId: 'frame',
                layout: SceneLayout(padding: 8),
                breakpoints: [
                  SceneBreakpoint(
                    minWidth: 640,
                    sizing: SceneSizing(),
                    layout: SceneLayout(padding: 12),
                  ),
                ],
                rect: SceneRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
              ),
              SceneNode(
                id: 'child',
                parentId: 'frame',
                componentId: 'text',
                primitive: ScenePrimitive.text,
                rect: SceneRect(x: 0.1, y: 0.1, width: 0.4, height: 0.2),
                properties: {'text': 'Hello'},
              ),
            ],
          ),
        ),
      );
    return SceneEditor(sceneFile, minHitTarget: minHitTarget);
  }

  testWidgets(
    'NodeLayoutInspector and NodeMotionInspector preserve invalid text across controller errors and apply drafts before removing breakpoints',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final root = Directory.systemTemp.createTempSync('studio-inspector-');
      addTearDown(() => root.deleteSync(recursive: true));
      final editor = createEditor(root);
      addTearDown(editor.dispose);

      await tester.pumpWidget(
        ShadcnApp(
          theme: ThemeData(colorScheme: ColorSchemes.darkZinc),
          home: Scaffold(
            child: Row(
              children: [
                SizedBox(
                  width: 340,
                  child: NodeInspector(
                    controller: editor.inspector,
                    componentCatalog: editor.componentCatalog,
                    editor: editor,
                    onApply: editor.tryApplyDraft,
                  ),
                ),
                const Expanded(
                  child: TextField(key: ValueKey('focus-sink')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Typing invalid text into Padding triggers showError -> NodeInspector rebuild.
      // didUpdateWidget must not overwrite 'abc' with the prior committed '8.0'.
      final paddingFinder = find.byKey(const ValueKey('layout-Padding'));
      await tester.ensureVisible(paddingFinder);
      await tester.enterText(paddingFinder, 'abc');
      await tester.tap(find.byKey(const ValueKey('focus-sink')));
      await tester.pumpAndSettle();

      expect(editor.inspector.error, contains('Padding must be a finite number'));
      expect(tester.widget<TextField>(paddingFinder).controller?.text, 'abc');

      // Expand Advanced layout -> Motion and verify invalid Duration ms is preserved.
      await tester.ensureVisible(find.text('Advanced layout'));
      await tester.tap(find.text('Advanced layout'));
      await tester.pumpAndSettle();
      final durationFinder = find.byKey(const ValueKey('motion-Duration ms'));
      await tester.ensureVisible(durationFinder);
      await tester.enterText(durationFinder, 'bad');
      await tester.tap(find.byKey(const ValueKey('focus-sink')));
      await tester.pumpAndSettle();

      expect(
        editor.inspector.error,
        contains('Duration ms must be an integer'),
      );
      expect(tester.widget<TextField>(durationFinder).controller?.text, 'bad');
      expect(editor.save(), isFalse);

      // Discard restores valid committed values when drafts are invalid.
      await tester.tap(find.byKey(const ValueKey('discard-inspector-draft')));
      await tester.pumpAndSettle();
      expect(editor.inspector.hasDraft, isFalse);
      expect(editor.inspector.error, isNull);

      // Now select a breakpoint in NodeLayoutInspector and verify Remove breakpoint
      // applies pending valid inspector drafts instead of dropping them.
      await tester.ensureVisible(find.text('Base layout'));
      await tester.tap(find.text('Base layout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Viewport ≥ 640 px').last);
      await tester.pumpAndSettle();

      editor.inspector.getField('Depth').text = '5';
      await tester.tap(find.byKey(const ValueKey('layout-remove-breakpoint')));
      await tester.pumpAndSettle();

      expect(editor.selectedNode.z, 5);
      expect(editor.selectedNode.breakpoints, isEmpty);
      expect(find.byType(NodeLayoutInspector), findsOneWidget);
    },
  );

  testWidgets('CodeInspector handles empty selection and toggles to whole scene cleanly', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('studio-code-empty-');
    addTearDown(() => root.deleteSync(recursive: true));
    final editor = createEditor(root);
    addTearDown(editor.dispose);

    editor.selectNodes({});

    await tester.pumpWidget(
      ShadcnApp(
        theme: ThemeData(colorScheme: ColorSchemes.darkZinc),
        home: Scaffold(
          child: SizedBox(
            width: 360,
            height: 600,
            child: CodeInspector(editor: editor),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No selection'), findsOneWidget);
    expect(find.text('Select a layer or switch to Scene.'), findsOneWidget);

    await tester.tap(find.text('Scene'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inspect-code-source')), findsOneWidget);
  });

  test('getDescendantIds collects nested hierarchy ids once and respects minHitTarget in reference geometry', () {
    final root = Directory.systemTemp.createTempSync('studio-editor-geom-');
    addTearDown(() => root.deleteSync(recursive: true));
    final editor = createEditor(root, minHitTarget: 64);
    addTearDown(editor.dispose);

    expect(getDescendantIds(editor.document, ['frame']), {'frame', 'child'});
    expect(editor.updateNodeText('child', ''), isFalse);
    expect(editor.updateNodeText('child', 'Updated'), isTrue);
  });
}
