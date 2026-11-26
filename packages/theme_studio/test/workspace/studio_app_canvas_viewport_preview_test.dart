import 'package:flutter/material.dart' as material;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/preview/studio_preview.dart';
import 'package:theme_studio/src/preview/studio_preview_host.dart';
import 'package:theme_studio/src/canvas/studio_canvas.dart';
import 'package:theme_studio/src/model/studio_canvas_presets.dart';
import 'package:theme_studio/src/ui/studio_form.dart';

import 'studio_app_test_harness.dart';

class _InputComponents implements GreeterThemeComponents {
  _InputComponents(this.host);
  final GreeterHost host;

  @override
  Widget build(BuildContext context, SceneNode node) => node.id == 'panel'
      ? material.TextField(
          key: const ValueKey('preview-input'),
          controller: host.credentialController,
          focusNode: host.credentialFocusNode,
        )
      : const Text('Preview label');
}

void main() {
  final harness = StudioAppTestHarness();
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  testWidgets(
    'responsive viewport resizes continuously without editing the authored canvas',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      final original = encodeSceneDocument(editor.document);
      await tester.tap(find.byKey(const ValueKey('canvas-responsive')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('responsive-width')),
        const Offset(-55, 0),
      );
      await tester.pumpAndSettle();
      final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(
        preview.viewportSize!.width,
        isNot(editor.document.canvas.referenceWidth),
      );
      expect(preview.readOnly, isTrue);
      expect(encodeSceneDocument(editor.document), original);
      expect(editor.canUndo, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'middle-button canvas panning preserves selection and document history',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      final label = find.byKey(const ValueKey('preview-label'));
      final before = tester.getTopLeft(label);
      final drag = await tester.startGesture(
        tester.getCenter(label),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await drag.moveBy(const Offset(30, 10));
      await drag.moveBy(const Offset(30, 10));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(label) - before, const Offset(60, 20));
      expect(editor.selectedId, 'panel');
      expect(editor.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quick resolution saves one edit and comparison keeps the authored reference canvas',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      tester
          .widget<StudioSelect<StudioCanvasPreset>>(
            find.byKey(const ValueKey('quick-resolution')),
          )
          .onChanged(StudioCanvasPreset.portrait);
      await tester.pumpAndSettle();
      expect(editor.document.canvas.referenceWidth, 1080);
      expect(editor.document.canvas.referenceHeight, 1920);
      editor.undo();
      await tester.pumpAndSettle();
      expect(editor.canUndo, isFalse);
      final reference = editor.document.canvas;
      await tester.tap(find.byKey(const ValueKey('canvas-view-compare')));
      await tester.pumpAndSettle();
      final previews = tester.widgetList<StudioPreview>(
        find.byType(StudioPreview),
      );
      expect(previews.length, 4);
      expect(previews.map((preview) => preview.viewportSize).toSet().length, 4);
      expect(
        previews.every(
          (preview) => identical(preview.document.canvas, reference),
        ),
        isTrue,
      );
      expect(editor.canUndo, isFalse);
      expect(editor.isDirty, isFalse);
      await tester.tap(find.byKey(const ValueKey('canvas-view-single')));
      await tester.pumpAndSettle();
      expect(find.byType(StudioPreview), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rulers create move delete and save guides as atomic edits', (
    tester,
  ) async {
    await harness.openStudio(tester);
    final editor = tester
        .widget<StudioCanvas>(find.byType(StudioCanvas))
        .editor!;
    await tester.tap(find.byKey(const ValueKey('canvas-tool-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('canvas-rulers')));
    await tester.pumpAndSettle();
    final ruler = find.byKey(const ValueKey('ruler-vertical'));
    final canvas = tester.getRect(find.byType(SceneRuntime));
    final gesture = await tester.startGesture(tester.getCenter(ruler));
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump();
    await gesture.moveTo(
      canvas.topLeft + Offset(canvas.width * .4, canvas.height * .3),
    );
    await tester.pump();
    expect(editor.document.guides, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(editor.document.guides.single.position, closeTo(.4, .001));
    editor.undo();
    expect(editor.canUndo, isFalse);
    editor.redo();
    editor.save();
    expect(
      decodeSceneDocument(harness.file.readAsStringSync()).guides,
      editor.document.guides,
    );
    final line = find.byKey(const ValueKey('guide-0'));
    await tester.drag(line, const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(editor.document.guides.single.position, greaterThan(.4));
    await tester.tap(line);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(editor.document.guides, isEmpty);
    editor.undo();
    expect(editor.document.guides.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview scenarios wake the canvas without editing the scene', (
    tester,
  ) async {
    await harness.openStudio(tester);
    final editor = tester
        .widget<StudioCanvas>(find.byType(StudioCanvas))
        .editor!;
    final original = encodeSceneDocument(editor.document);
    await tester.tap(find.text('State: Login'));
    await tester.pumpAndSettle();
    for (final scenario in [
      ...StudioPreviewScenario.values.skip(1),
      StudioPreviewScenario.password,
    ]) {
      await tester.tap(find.byKey(const ValueKey('preview-scenario')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(scenario.label),
        scenario == StudioPreviewScenario.password ? -80 : 80,
        scrollable: find
            .descendant(
              of: find.byType(SelectPopup<StudioPreviewScenario>),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(scenario.label).last);
      await tester.pumpAndSettle();
      final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(preview.scenario, scenario);
      expect(preview.dormant, isFalse);
      expect(encodeSceneDocument(editor.document), original);
      expect(editor.canUndo, isFalse);
      expect(editor.isDirty, isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'interactive preview retains controls and prevents geometry edits',
    (tester) async {
      late GreeterHost host;
      await harness.openStudio(
        tester,
        themeBuilder: ({Color? seed, SceneDocument? document}) =>
            buildStudioTestTheme(
              document: document,
              components: (context) {
                host = context.host;
                return _InputComponents(host);
              },
            ),
      );
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      final original = encodeSceneDocument(editor.document);
      final controller = host.credentialController;
      await tester.tap(find.byKey(const ValueKey('canvas-preview')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).interactive,
        isTrue,
      );
      expect(find.byKey(const ValueKey('resize-topLeft')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('preview-input')));
      await tester.pump();
      expect(host.credentialFocusNode.hasFocus, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('preview-input')),
        'Preview only',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(encodeSceneDocument(editor.document), original);
      expect(editor.canUndo, isFalse);
      await tester.tap(find.byKey(const ValueKey('canvas-preview')));
      await tester.pumpAndSettle();
      expect(host.credentialController, same(controller));
      expect(host.credentialFocusNode.hasFocus, isFalse);
      expect(find.byKey(const ValueKey('resize-topLeft')), findsOneWidget);
      expect(editor.isDirty, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preview wake motion reverses and respects theme and system policy',
    (tester) async {
      harness.file.writeAsStringSync(
        encodeSceneDocument(
          studioTestDocument.copyWith(
            background: const SceneBackground(
              kind: SceneBackgroundKind.solid,
              blurSigma: 12,
            ),
          ),
        ),
      );
      var disabled = false;
      await harness.openStudio(
        tester,
        themeBuilder: ({Color? seed, SceneDocument? document}) =>
            buildStudioTestTheme(
              document: document,
              mediumMotion: const Duration(milliseconds: 400),
              disableAnimations: disabled,
            ),
      );
      SceneRuntime getRuntime() =>
          tester.widget<SceneRuntime>(find.byType(SceneRuntime));
      expect(
        MediaQuery.of(tester.element(find.byType(SceneRuntime)))
            .disableAnimations,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('canvas-preview')));
      await tester.pumpAndSettle();
      expect(
        MediaQuery.of(tester.element(find.byType(SceneRuntime)))
            .disableAnimations,
        isFalse,
      );
      await tester.tap(find.text('State: Login'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final midway = getRuntime().backgroundBlurSigma!.value;
      expect(midway, greaterThan(0));
      expect(midway, lessThan(12));
      await tester.tap(find.text('State: Dormant'));
      await tester.pumpAndSettle();
      expect(getRuntime().backgroundBlurSigma!.value, 12);
      disabled = true;
      final reload = tester.binding.reassembleApplication();
      await tester.pumpAndSettle();
      await reload;
      await tester.tap(find.text('State: Login'));
      await tester.pump();
      expect(getRuntime().backgroundBlurSigma!.value, 0);
      disabled = false;
      final refresh = tester.binding.reassembleApplication();
      await tester.pumpAndSettle();
      await refresh;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('State: Dormant'));
      await tester.pump();
      expect(getRuntime().backgroundBlurSigma!.value, 12);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fit keeps the scene centered when the window and panels resize',
    (tester) async {
      await harness.openStudio(tester);
      final scene = find.byType(SceneRuntime);
      final viewport = find.byKey(const ValueKey('studio-viewport'));
      void checkFit() {
        final sceneRect = tester.getRect(scene);
        final viewportRect = tester.getRect(viewport);
        expect(
          (sceneRect.center - viewportRect.center).distance,
          lessThan(1e-6),
        );
        expect(sceneRect.width, lessThanOrEqualTo(viewportRect.width + 1e-6));
        expect(sceneRect.height, lessThanOrEqualTo(viewportRect.height + 1e-6));
        expect(find.text('Saved'), findsOneWidget);
      }

      for (final size in [
        const Size(1100, 900),
        const Size(1800, 900),
        const Size(1400, 1200),
        const Size(1400, 900),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        checkFit();
      }
      final divider = find.byWidgetPredicate(
        (widget) =>
            widget is MouseRegion &&
            widget.cursor == SystemMouseCursors.resizeColumn,
      );
      await tester.drag(divider.first, const Offset(100, 0));
      await tester.pumpAndSettle();
      checkFit();
      expect(
        harness.file.readAsStringSync(),
        encodeSceneDocument(studioTestDocument),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zoom and pan preserve geometry, pointer anchor and handle size',
    (tester) async {
      await harness.openStudio(tester);
      final scene = find.byType(SceneRuntime);
      final originalRect = tester.getRect(scene);
      final handle = find.byKey(const ValueKey('resize-right'));
      final originalHandleSize = tester.getRect(handle).size;
      final viewport = find.byKey(const ValueKey('studio-viewport'));
      final pointer = tester.getCenter(viewport) + const Offset(70, 20);
      final canvas = tester.renderObject<RenderBox>(scene);
      final local = canvas.globalToLocal(pointer);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: pointer,
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect((canvas.globalToLocal(pointer) - local).distance, lessThan(1e-6));
      expect(tester.getRect(scene).width, greaterThan(originalRect.width));
      expect(
        tester.getRect(handle).size.width,
        closeTo(originalHandleSize.width, 1e-6),
      );
      await tester.tap(find.byKey(const ValueKey('zoom-fit')));
      await tester.pumpAndSettle();
      expect(tester.getRect(scene), originalRect);
      await tester.tap(find.byKey(const ValueKey('canvas-hand')));
      await tester.pumpAndSettle();
      await tester.drag(viewport, const Offset(60, 30));
      await tester.pumpAndSettle();
      expect(
        (tester.getRect(scene).topLeft -
                originalRect.topLeft -
                const Offset(60, 30))
            .distance,
        lessThan(1e-6),
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(
        encodeSceneDocument(
          tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
        ),
        encodeSceneDocument(studioTestDocument),
      );
      await tester.tap(find.byKey(const ValueKey('zoom-fit')));
      await tester.pumpAndSettle();
      expect(tester.getRect(scene), originalRect);
      await tester.tap(find.byKey(const ValueKey('canvas-hand')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('canvas-tool-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('zoom-actual-size')));
      await tester.pumpAndSettle();
      expect(tester.getRect(scene).width, closeTo(1280, 1e-6));
      await tester.drag(handle, const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .rect
            .width,
        closeTo(0.3 + 40 / 1280, 1e-8),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canvas shortcuts nudge, undo, duplicate, delete, save and leave text editing alone',
    (tester) async {
      await harness.openStudio(tester);
      await tester.tap(find.byKey(const ValueKey('preview-panel')));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      var preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(
        preview.document.nodes.first.rect.x,
        closeTo(0.1 + 1 / 1280, 1e-8),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .document
            .nodes
            .first
            .rect
            .y,
        closeTo(0.1 + 10 / 720, 1e-8),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).panEnabled,
        isTrue,
      );
      await tester.drag(
        find.byKey(const ValueKey('studio-viewport')),
        const Offset(20, 10),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).panEnabled,
        isFalse,
      );
      expect(find.text('Saved'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pumpAndSettle();
      final canvas = find.byKey(const ValueKey('studio-viewport'));
      await tester.drag(canvas, const Offset(40, 20));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(preview.selectedId, 'panel-copy');
      expect(
        decodeSceneDocument(harness.file.readAsStringSync()).nodes,
        hasLength(3),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).document.nodes,
        hasLength(2),
      );
      final before = tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .document;
      await tester.tap(find.byKey(const ValueKey('field-X')));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
        same(before),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dormant preview respects visibility and hidden nodes remain selectable in layers',
    (tester) async {
      await harness.openStudio(tester);
      await tester.tap(find.text('State: Login'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preview-label')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('layer-label')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).selectedId,
        'label',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
