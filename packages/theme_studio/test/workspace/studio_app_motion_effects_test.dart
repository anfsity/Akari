import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/canvas/studio_canvas.dart';
import 'package:theme_studio/src/timeline/studio_timeline.dart';

import 'studio_app_test_harness.dart';

class _ParameterizedBackground extends BackgroundRenderer {
  @override
  List<BackgroundParameter> get parameters => const [
    BackgroundParameter(
      id: 'intensity',
      label: 'Intensity',
      minimum: 0,
      maximum: 1,
      defaultValue: .5,
    ),
  ];
  @override
  Widget build(BuildContext context, SceneBackground background) => ColoredBox(
    key: const ValueKey('parameterized-background'),
    color: Color.lerp(
      const Color(0xff000000),
      const Color(0xffffffff),
      parameters.single.getValue(background),
    )!,
  );
}

void main() {
  final harness = StudioAppTestHarness();
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  testWidgets(
    'style sliders preview live and create one shared-token revision',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await tester.ensureVisible(find.text('Visual style'));
      await tester.tap(find.text('Visual style'));
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('style-Corner radius'));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(editor.document.styleTokens, isEmpty);
      expect(
        editor.previewDocument.styleTokens.values.single.radius,
        greaterThan(0),
      );
      expect(
        tester
            .widget<SceneRuntime>(find.byType(SceneRuntime))
            .document
            .styleTokens,
        isNotEmpty,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(editor.document.styleTokens.values.single.radius, greaterThan(0));
      editor.undo();
      expect(editor.canUndo, isFalse);
      expect(editor.document.styleTokens, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'timeline tracks drag once, edit keyframes and persist through undo and save',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await tester.tap(find.byKey(const ValueKey('canvas-timeline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('timeline-add-track')));
      await tester.pumpAndSettle();
      expect(
        editor.selectedNode.tracks.single.property,
        SceneMotionProperty.opacity,
      );
      final initial = encodeSceneDocument(editor.document);
      final block = find.byKey(const ValueKey('timeline-block-panel'));
      final gesture = await tester.startGesture(
        tester.getTopLeft(block) + const Offset(8, 10),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(encodeSceneDocument(editor.document), initial);
      expect(
        editor.previewDocument.nodes.first.motionTiming.delayMs,
        greaterThan(0),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(editor.document.nodes.first.motionTiming.delayMs, greaterThan(0));
      editor.undo();
      await tester.pumpAndSettle();
      expect(encodeSceneDocument(editor.document), initial);
      final frame = find.byKey(const ValueKey('keyframe-panel-0-1'));
      await tester.tap(frame);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(frame);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('keyframe-value')),
        '.4',
      );
      await tester.tap(find.text('Apply').last);
      await tester.pumpAndSettle();
      expect(editor.selectedNode.tracks.single.keyframes.last.value, .4);
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync())
            .nodes
            .first
            .tracks
            .single
            .keyframes
            .last
            .value,
        .4,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'timeline scrubbing and state transitions never edit scene history',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await tester.tap(find.byKey(const ValueKey('canvas-timeline')));
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('timeline-scrubber')),
      );
      slider.onChanged!(const SliderValue.single(.5));
      await tester.pump();
      expect(
        tester
            .widget<SceneRuntime>(find.byType(SceneRuntime))
            .playback!
            .elapsed
            .inMilliseconds,
        750,
      );
      tester
          .widget<StudioTimeline>(find.byType(StudioTimeline))
          .onTransitionChanged(StudioTransition.error);
      await tester.pump();
      final runtime = tester.widget<SceneRuntime>(find.byType(SceneRuntime));
      expect(runtime.activePredicates, contains(ScenePredicate.isAuthError));
      expect(runtime.playback!.from, contains(ScenePredicate.isAuthSubmitting));
      await tester.tap(find.byKey(const ValueKey('timeline-play')));
      await tester.pumpAndSettle();
      expect(editor.canUndo, isFalse);
      expect(editor.isDirty, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'motion fields preserve inherited easing when editing duration and delay',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await tester.ensureVisible(find.text('Advanced layout'));
      await tester.tap(find.text('Advanced layout'));
      await tester.pumpAndSettle();
      final duration = find.byKey(const ValueKey('motion-Duration ms'));
      await tester.ensureVisible(duration);
      await tester.enterText(duration, '800');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(editor.selectedNode.motionTiming.durationMs, 800);
      expect(editor.selectedNode.motionTiming.curve, isNull);
      final delay = find.byKey(const ValueKey('motion-Delay ms'));
      await tester.ensureVisible(delay);
      await tester.enterText(delay, '160');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(editor.selectedNode.motionTiming.delayMs, 160);
      editor.undo();
      expect(editor.selectedNode.motionTiming.durationMs, 800);
      editor.undo();
      expect(editor.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'state graph adds edits undoes and saves visual transition edges',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await tester.tap(find.byKey(const ValueKey('canvas-state-graph')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('graph-add-transition')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transition-duration')),
        '450',
      );
      await tester.tap(find.byKey(const ValueKey('save-transition')));
      await tester.pumpAndSettle();
      expect(editor.selectedNode.transitions.single.timing.durationMs, 450);
      expect(find.byKey(const ValueKey('graph-edge-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('graph-edge-0')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transition-duration')),
        '700',
      );
      await tester.tap(find.byKey(const ValueKey('save-transition')));
      await tester.pumpAndSettle();
      expect(editor.selectedNode.transitions.single.timing.durationMs, 700);
      editor.undo();
      await tester.pumpAndSettle();
      expect(editor.selectedNode.transitions.single.timing.durationMs, 450);
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync())
            .nodes
            .first
            .transitions
            .single
            .timing
            .durationMs,
        450,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'state flow previews outcomes and authored state rules save with history',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await tester.ensureVisible(find.text('State rules'));
      await tester.tap(find.text('State rules'));
      await tester.pumpAndSettle();
      final add = find.byKey(const ValueKey('add-state-effect'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(editor.selectedNode.stateEffects, {
        ScenePredicate.isAuthError: SceneStateEffect.shake,
      });
      editor.save();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync())
            .nodes
            .first
            .stateEffects,
        editor.selectedNode.stateEffects,
      );
      await tester.tap(find.byKey(const ValueKey('canvas-state-graph')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('graph-Error')));
      await tester.tap(find.byKey(const ValueKey('graph-Error')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SceneRuntime>(find.byType(SceneRuntime)).activePredicates,
        contains(ScenePredicate.isAuthError),
      );
      editor.undo();
      expect(editor.selectedNode.stateEffects, isEmpty);
      expect(editor.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shader playground keeps drafts out of history and reports compiler setup errors',
    (tester) async {
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      final original = encodeSceneDocument(editor.document);
      await tester.tap(find.text('Effects'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-shader-playground')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('shader-source')),
        'invalid shader',
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('shader-compile')));
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump();
          if (find
              .byKey(const ValueKey('shader-diagnostic'))
              .evaluate()
              .isNotEmpty) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shader-diagnostic')), findsOneWidget);
      expect(encodeSceneDocument(editor.document), original);
      expect(editor.canUndo, false);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'effect parameters preview through the renderer and save as one revision',
    (tester) async {
      await harness.openStudio(
        tester,
        themeBuilder: ({Color? seed, SceneDocument? document}) {
          final theme = buildStudioTestTheme(seed: seed, document: document);
          return theme.copyWith(
            bundle: theme.bundle.copyWith(
              backgrounds: {
                SceneBackgroundKind.solid: _ParameterizedBackground(),
              },
            ),
          );
        },
      );
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await tester.tap(find.text('Effects'));
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('effect-intensity'));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final original = tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('parameterized-background')),
          )
          .color;
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(editor.document.background.parameters, isEmpty);
      expect(
        tester
            .widget<ColoredBox>(
              find.byKey(const ValueKey('parameterized-background')),
            )
            .color,
        isNot(original),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        editor.document.background.parameters['intensity'],
        greaterThan(.5),
      );
      editor.undo();
      expect(editor.document.background.parameters, isEmpty);
      expect(editor.canUndo, isFalse);
      editor.redo();
      editor.save();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync())
            .background
            .parameters['intensity'],
        greaterThan(.5),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
