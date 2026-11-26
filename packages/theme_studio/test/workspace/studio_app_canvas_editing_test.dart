import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/preview/studio_preview.dart';
import 'package:theme_studio/src/inspector/node_inspector.dart';
import 'package:theme_studio/src/canvas/studio_canvas.dart';
import 'package:theme_studio/src/authoring/studio_components.dart';

import 'studio_app_test_harness.dart';

void main() {
  final harness = StudioAppTestHarness();
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  testWidgets(
    'Shift selection, marquee, grouping and frame layout work on canvas',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.byKey(const ValueKey('preview-label')));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(editor.selectedIds, {'panel', 'label'});
      await tester.tap(find.byKey(const ValueKey('group-selection')));
      await tester.pumpAndSettle();
      expect(editor.selectedNode.layout, isNotNull);
      expect(find.text('Frame layout'), findsOneWidget);
      expect(find.byKey(const ValueKey('layer-list')), findsOneWidget);
      editor.undo();
      editor.selectNodes({});
      await tester.pumpAndSettle();
      final canvas = tester.getRect(find.byType(SceneRuntime));
      final gesture = await tester.startGesture(
        canvas.topLeft + const Offset(3, 3),
      );
      await gesture.moveTo(canvas.bottomRight - const Offset(3, 3));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(editor.selectedIds, {'panel', 'label'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('canvas text edits commit once and Escape discards the draft', (
    tester,
  ) async {
    await harness.openStudio(
      tester,
      themeBuilder: ({Color? seed, SceneDocument? document}) =>
          buildStudioTestTheme(
            seed: seed,
            document: document,
            componentCatalog: studioEditableCatalog,
          ),
    );
    final editor = tester
        .widget<StudioCanvas>(find.byType(StudioCanvas))
        .editor!;
    final node = find.byKey(const ValueKey('preview-panel'));
    await tester.tap(node);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(node);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('canvas-text-editor'));
    expect(input, findsOneWidget);
    await tester.enterText(input, 'Hello canvas');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(editor.selectedNode.properties['text'], 'Hello canvas');
    editor.undo();
    expect(editor.canUndo, isFalse);
    await tester.tap(node);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(node);
    await tester.pumpAndSettle();
    await tester.enterText(input, 'Discard me');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(editor.selectedNode.properties['text'], isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'canvas commands also work from layer rows without intercepting text edits',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await tester.tap(find.byKey(const ValueKey('layer-label')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(editor.document.nodes.length, 2);
      expect(editor.selectedId, 'label');
      await tester.enterText(find.byKey(const ValueKey('field-X')), 'draft');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(editor.document.nodes.length, 2);
      expect(editor.inspector.hasDraft, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'layer rows drag into frames and back to the root with atomic undo',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      editor.createComponent(StudioComponent.frame);
      await tester.pumpAndSettle();
      final source = find.byKey(const ValueKey('layer-label'));
      final target = find.byKey(const ValueKey('layer-frame'));
      final drag = await tester.startGesture(tester.getCenter(source));
      await drag.moveBy(const Offset(40, 0));
      await tester.pump();
      await drag.moveTo(tester.getCenter(target));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(
        editor.document.nodes.firstWhere((node) => node.id == 'label').parentId,
        'frame',
      );
      final unnest = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('layer-label'))),
      );
      await unnest.moveBy(const Offset(40, 0));
      await tester.pump();
      await unnest.moveTo(
        tester.getCenter(find.byKey(const ValueKey('layer-root-drop'))),
      );
      await tester.pump();
      await unnest.up();
      await tester.pumpAndSettle();
      expect(editor.selectedNode.parentId, isNull);
      editor.undo();
      expect(editor.selectedNode.parentId, 'frame');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'blank scenes and reusable primitives author independently of layout slots',
    (tester) async {
      await harness.openStudio(tester);
      final original = harness.file.readAsStringSync();
      await tester.tap(find.byKey(const ValueKey('studio-scene-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-scene')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('new-scene-name')),
        'free-canvas',
      );
      await tester.tap(find.byKey(const ValueKey('confirm-new-scene')));
      await tester.pumpAndSettle();
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      expect(editor.document.id, 'free-canvas');
      expect(editor.layout, isNull);
      expect(harness.file.readAsStringSync(), original);
      await tester.tap(find.byKey(const ValueKey('sidebar-components')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-component-text')));
      await tester.pumpAndSettle();
      expect(editor.selectedNode.primitive, ScenePrimitive.text);
      expect(find.text('New text'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('add-component-text')));
      await tester.pumpAndSettle();
      expect(editor.selectedId, 'text-2');
      editor.createComponent(StudioComponent.rectangle);
      editor.createComponent(StudioComponent.circle);
      editor.undo();
      expect(
        editor.document.nodes.any(
          (node) => node.primitive == ScenePrimitive.circle,
        ),
        isFalse,
      );
      editor.redo();
      expect(editor.save(), isTrue);
      expect(
        decodeSceneDocument(editor.file.readAsStringSync())
            .nodes
            .last
            .primitive,
        ScenePrimitive.circle,
      );
      expect(harness.file.readAsStringSync(), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'drag uses canvas scale, stays in bounds and creates one undo step',
    (tester) async {
      await harness.openStudio(tester);
      final target = find.byKey(const ValueKey('preview-panel'));
      final gesture = await tester.startGesture(tester.getCenter(target));
      await gesture.moveBy(const Offset(40, 20));
      await tester.pump();
      await gesture.moveBy(const Offset(2000, 2000));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final moved = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(moved.document.nodes.first.rect.x, closeTo(0.7, 0.00001));
      expect(moved.document.nodes.first.rect.y, closeTo(0.6, 0.00001));
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .rect
            .x,
        0.1,
      );
      expect(find.text('Saved'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync()).nodes.first.rect.x,
        closeTo(0.7, 0.00001),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live drag updates position inputs without rebuilding inspector or committing revisions',
    (tester) async {
      await harness.openStudio(tester);
      final inspector = tester
          .widget<NodeInspector>(find.byType(NodeInspector))
          .controller;
      final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      final form = find.byKey(const ValueKey('node-inspector-form'));
      final formWidget = tester.widget(form);
      final widthController = inspector.getField('Width');
      var inspectorNotifications = 0;
      var widthNotifications = 0;
      inspector.addListener(() => inspectorNotifications++);
      widthController.addListener(() => widthNotifications++);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('preview-panel'))),
      );
      await gesture.moveBy(const Offset(40, 20));
      await tester.pump();
      final firstX = double.parse(inspector.getField('X').text);
      expect(firstX, greaterThan(0.1));
      await gesture.moveBy(const Offset(30, 15));
      await tester.pump();
      expect(double.parse(inspector.getField('X').text), greaterThan(firstX));
      expect(double.parse(inspector.getField('Y').text), greaterThan(0.1));
      expect(inspector.hasDraft, isFalse);
      expect(inspectorNotifications, 0);
      expect(widthNotifications, 0);
      expect(tester.widget(form), same(formWidget));
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)),
        same(preview),
      );
      expect(preview.document.nodes.first.rect.x, 0.1);
      expect(find.text('Saved'), findsOneWidget);
      expect(
        tester
            .widget<OutlineButton>(find.byKey(const ValueKey('toolbar-undo')))
            .onPressed,
        isNull,
      );
      final liveX = double.parse(inspector.getField('X').text);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .rect
            .x,
        closeTo(liveX / 1280, 1e-7),
      );
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(inspector.getField('X').text, '128');
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dragging a transformed node follows canvas coordinates', (
    tester,
  ) async {
    harness.file.writeAsStringSync(
      encodeSceneDocument(
        studioTestDocument.copyWith(
          nodes: [
            studioTestDocument.nodes.first.copyWith(
              transform: const SceneTransform(
                rotationZ: 0.6,
                scaleX: 1.2,
                scaleY: 0.8,
              ),
            ),
            studioTestDocument.nodes.last,
          ],
        ),
      ),
    );
    await harness.openStudio(tester);
    final canvasRect = tester.getRect(find.byType(SceneRuntime));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.drag(
      find.byKey(const ValueKey('preview-panel')),
      const Offset(60, 30),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    final node = tester
        .widget<StudioPreview>(find.byType(StudioPreview))
        .document
        .nodes
        .first;
    expect(node.rect.x, closeTo(0.1 + 60 / canvasRect.width, 0.00001));
    expect(node.rect.y, closeTo(0.1 + 30 / canvasRect.height, 0.00001));
    expect(node.transform.rotationZ, 0.6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resize relayouts text, cancels and commits one undo step', (
    tester,
  ) async {
    await harness.openStudio(tester);
    final inspector = tester
        .widget<NodeInspector>(find.byType(NodeInspector))
        .controller;
    final handle = find.byKey(const ValueKey('resize-right'));
    final canvas = tester.getRect(find.byType(SceneRuntime));
    final text = find.descendant(
      of: find.byKey(const ValueKey('preview-panel')),
      matching: find.byType(Text),
    );
    final style = tester.widget<Text>(text).style;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    final live = tester
        .widget<SceneRuntime>(find.byType(SceneRuntime))
        .document
        .nodes
        .first;
    expect(live.rect.width, closeTo(0.3 + 60 / canvas.width, 1e-8));
    expect(live.rect.height, 0.4);
    expect(live.transform.isIdentity, isTrue);
    expect(
      double.parse(inspector.getField('Width').text) / 1280,
      closeTo(live.rect.width, 1e-7),
    );
    expect(inspector.hasDraft, isFalse);
    expect(tester.widget<Text>(text).style, style);
    expect(find.text('Saved'), findsOneWidget);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(inspector.getField('Width').text, '384');
    await tester.drag(handle, const Offset(60, 0));
    await tester.pumpAndSettle();
    final changed = tester
        .widget<StudioPreview>(find.byType(StudioPreview))
        .document;
    expect(changed.nodes.first.rect.width, closeTo(live.rect.width, 1e-8));
    await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(
      tester
          .widget<OutlineButton>(find.byKey(const ValueKey('toolbar-undo')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save scene'));
    await tester.pumpAndSettle();
    expect(
      encodeSceneDocument(decodeSceneDocument(harness.file.readAsStringSync())),
      encodeSceneDocument(changed),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'aspect lock and Shift preserve ratio, hidden selections have no handles',
    (tester) async {
      await harness.openStudio(tester);
      await tester.tap(find.byKey(const ValueKey('canvas-tool-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lock-aspect-ratio')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('resize-bottomRight')),
        const Offset(50, 10),
      );
      await tester.pumpAndSettle();
      var node = tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first;
      expect(node.rect.width / node.rect.height, closeTo(0.75, 1e-8));
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('canvas-tool-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lock-aspect-ratio')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.drag(
        find.byKey(const ValueKey('resize-bottomRight')),
        const Offset(50, 10),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      node = tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first;
      expect(node.rect.width / node.rect.height, closeTo(0.75, 1e-8));
      await tester.tap(find.byKey(const ValueKey('preview-label')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('State: Login'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('resize-right')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled drags preserve the scene and history', (tester) async {
    await harness.openStudio(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('preview-panel'))),
    );
    await gesture.moveBy(const Offset(60, 30));
    await tester.pump();
    final inspector = tester
        .widget<NodeInspector>(find.byType(NodeInspector))
        .controller;
    expect(double.parse(inspector.getField('X').text), greaterThan(0.1));
    await gesture.cancel();
    await tester.pumpAndSettle();
    final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
    expect(
      encodeSceneDocument(preview.document),
      encodeSceneDocument(studioTestDocument),
    );
    expect(inspector.getField('X').text, '128');
    expect(inspector.getField('Y').text, '72');
    expect(inspector.hasDraft, isFalse);
    expect(find.text('Saved'), findsOneWidget);
    expect(
      tester
          .widget<OutlineButton>(find.byKey(const ValueKey('toolbar-undo')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid inspector drafts block dragging', (tester) async {
    await harness.openStudio(tester);
    await tester.enterText(find.byKey(const ValueKey('field-Width')), '2560');
    await tester.drag(
      find.byKey(const ValueKey('preview-panel')),
      const Offset(80, 40),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first
          .rect
          .x,
      0.1,
    );
    expect(find.textContaining('non-normalized rect'), findsOneWidget);
  });

  for (final (tool, fields) in [
    (StudioCanvasTool.scale, ['Scale X', 'Scale Y']),
    (StudioCanvasTool.rotate, ['Rotate Z']),
    (StudioCanvasTool.rotate3d, ['Rotate X', 'Rotate Y']),
  ]) {
    testWidgets('${tool.label} drag previews, cancels, commits and saves', (
      tester,
    ) async {
      await harness.openStudio(tester);
      await tester.tap(find.byKey(const ValueKey('canvas-tool-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('tool-menu-${tool.name}')));
      await tester.pumpAndSettle();
      final inspector = tester
          .widget<NodeInspector>(find.byType(NodeInspector))
          .controller;
      final original = encodeSceneDocument(studioTestDocument);
      final target = find.byKey(const ValueKey('preview-panel'));
      final canvas = tester.getRect(find.byType(SceneRuntime));
      var inspectorNotifications = 0;
      inspector.addListener(() => inspectorNotifications++);
      final gesture = await tester.startGesture(tester.getCenter(target));
      await gesture.moveBy(const Offset(40, 20));
      await tester.pump();
      final first = double.parse(inspector.getField(fields.first).text);
      await gesture.moveBy(const Offset(20, 10));
      await tester.pump();
      expect(double.parse(inspector.getField(fields.first).text), isNot(first));
      expect(inspectorNotifications, 0);
      expect(inspector.hasDraft, isFalse);
      expect(find.text('Saved'), findsOneWidget);
      expect(
        encodeSceneDocument(
          tester.widget<SceneRuntime>(find.byType(SceneRuntime)).document,
        ),
        isNot(original),
      );
      expect(
        encodeSceneDocument(
          tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
        ),
        original,
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(
        encodeSceneDocument(
          tester.widget<SceneRuntime>(find.byType(SceneRuntime)).document,
        ),
        original,
      );
      for (final field in fields) {
        expect(
          inspector.getField(field).text,
          tool == StudioCanvasTool.scale ? '1.0' : '0.0',
        );
      }
      expect(find.text('Saved'), findsOneWidget);
      expect(inspector.hasDraft, isFalse);

      await tester.drag(target, const Offset(60, 30));
      await tester.pumpAndSettle();
      final node = tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first;
      expect(node.rect.x, 0.1);
      expect(node.rect.y, 0.1);
      expect(node.rect.width, 0.3);
      expect(node.rect.height, 0.4);
      expect(
        node.transform.scaleX,
        closeTo(
          tool == StudioCanvasTool.scale ? 1 + 180 / canvas.width : 1,
          0.00001,
        ),
      );
      expect(
        node.transform.scaleY,
        closeTo(
          tool == StudioCanvasTool.scale ? 1 + 90 / canvas.height : 1,
          0.00001,
        ),
      );
      expect(
        node.transform.rotationZ,
        closeTo(
          tool == StudioCanvasTool.rotate ? 21600 / canvas.width : 0,
          0.00001,
        ),
      );
      expect(
        node.transform.rotationX,
        closeTo(
          tool == StudioCanvasTool.rotate3d ? -5400 / canvas.height : 0,
          0.00001,
        ),
      );
      expect(
        node.transform.rotationY,
        closeTo(
          tool == StudioCanvasTool.rotate3d ? 10800 / canvas.width : 0,
          0.00001,
        ),
      );
      final changed = encodeSceneDocument(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
      );
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      expect(
        encodeSceneDocument(
          tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
        ),
        original,
      );
      expect(
        tester
            .widget<OutlineButton>(find.byKey(const ValueKey('toolbar-undo')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        encodeSceneDocument(
          decodeSceneDocument(harness.file.readAsStringSync()),
        ),
        changed,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('scaling preserves mirrored axes and authored transforms', (
    tester,
  ) async {
    const transform = SceneTransform(
      scaleX: -1.2,
      scaleY: 0.8,
      rotationX: 10,
      rotationY: 15,
      rotationZ: 20,
      translateX: 12,
      translateY: 6,
      pivotX: 0.4,
      pivotY: 0.6,
      perspective: 0.0007,
    );
    final document = studioTestDocument.copyWith(
      nodes: [
        studioTestDocument.nodes.first.copyWith(transform: transform),
        studioTestDocument.nodes.last,
      ],
    );
    harness.file.writeAsStringSync(encodeSceneDocument(document));
    await harness.openStudio(tester);
    await tester.tap(find.byKey(const ValueKey('canvas-tool-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tool-menu-scale')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('preview-panel')),
      const Offset(-2000, -2000),
    );
    await tester.pumpAndSettle();
    final node = tester
        .widget<StudioPreview>(find.byType(StudioPreview))
        .document
        .nodes
        .first;
    expect(node.transform.scaleX, -0.01);
    expect(node.transform.scaleY, 0.01);
    expect(
      encodeSceneDocument(
        document.copyWith(
          nodes: [
            node.copyWith(
              transform: node.transform.copyWith(
                scaleX: transform.scaleX,
                scaleY: transform.scaleY,
              ),
            ),
            document.nodes.last,
          ],
        ),
      ),
      encodeSceneDocument(document),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reset scale repairs stretched nodes and preserves other transforms',
    (tester) async {
      const transform = SceneTransform(
        scaleX: 1.4,
        scaleY: 0.7,
        rotationZ: 20,
        pivotX: 0.3,
      );
      final original = studioTestDocument.copyWith(
        nodes: [
          studioTestDocument.nodes.first.copyWith(transform: transform),
          studioTestDocument.nodes.last,
        ],
      );
      harness.file.writeAsStringSync(encodeSceneDocument(original));
      await harness.openStudio(tester);
      final scroll = find
          .descendant(
            of: find.byType(NodeInspector),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Advanced layout'),
        200,
        scrollable: scroll,
      );
      await tester.tap(find.text('Advanced layout'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('reset-node-scale')),
        200,
        scrollable: scroll,
      );
      await tester.tap(find.byKey(const ValueKey('reset-node-scale')));
      await tester.pumpAndSettle();
      final node = tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document
          .nodes
          .first;
      expect(node.transform.scaleX, 1);
      expect(node.transform.scaleY, 1);
      expect(node.transform.rotationZ, 20);
      expect(node.transform.pivotX, 0.3);
      expect(node.rect.width, 0.3);
      expect(node.rect.height, 0.4);
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(
        encodeSceneDocument(
          tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
        ),
        encodeSceneDocument(original),
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
