import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/scene_editor.dart';
import 'package:theme_studio/src/studio_timeline.dart';
import 'package:theme_studio/src/studio_timeline_tracks.dart';

void main() {
  late Directory directory;
  late SceneEditor editor;
  late ValueNotifier<Duration> elapsed;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('studio-timeline-');
    final file = File('${directory.path}/test.scene.json')
      ..writeAsStringSync(
        encodeSceneDocument(
          const SceneDocument(
            id: 'test',
            version: currentSceneVersion,
            canvas: SceneCanvas(),
            background: SceneBackground(kind: SceneBackgroundKind.solid),
            nodes: [
              SceneNode(
                id: 'plain',
                componentId: 'panel',
                rect: SceneRect(x: 0, y: 0, width: 1, height: 1),
                motionTiming: SceneMotionTiming(durationMs: 1000),
                tracks: [
                  SceneMotionTrack(
                    property: SceneMotionProperty.opacity,
                    keyframes: [
                      SceneKeyframe(timeMs: 0, value: 0),
                      SceneKeyframe(timeMs: 250, value: .25),
                      SceneKeyframe(timeMs: 1000, value: 1),
                    ],
                  ),
                ],
              ),
              SceneNode(
                id: 'delayed',
                componentId: 'panel',
                rect: SceneRect(x: 0, y: 0, width: 1, height: 1),
                motionTiming: SceneMotionTiming(delayMs: 100, durationMs: 900),
                tracks: [
                  SceneMotionTrack(
                    property: SceneMotionProperty.opacity,
                    keyframes: [
                      SceneKeyframe(timeMs: 0, value: 0),
                      SceneKeyframe(timeMs: 400, value: .5),
                      SceneKeyframe(timeMs: 900, value: 1),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    editor = SceneEditor(file);
    elapsed = ValueNotifier(Duration.zero);
  });

  tearDown(() {
    elapsed.dispose();
    editor.dispose();
    directory.deleteSync(recursive: true);
  });

  Future<void> pumpTimeline(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      ShadcnApp(
        home: Scaffold(
          child: Center(
            child: SizedBox(
              width: width,
              child: ListenableBuilder(
                listenable: editor,
                builder: (context, _) => ValueListenableBuilder<Duration>(
                  valueListenable: elapsed,
                  builder: (context, value, _) => StudioTimeline(
                    editor: editor,
                    duration: const Duration(seconds: 1),
                    fallbackDuration: const Duration(seconds: 1),
                    elapsed: value,
                    transition: StudioTransition.entrance,
                    onTimeChanged: (value) => elapsed.value = value,
                    onTransitionChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final playhead = find
      .descendant(
        of: find.byType(StudioTimelineTracks),
        matching: find.byType(IgnorePointer),
      )
      .last;

  testWidgets(
    'keyframes, playhead and scrubbing agree across viewport widths',
    (tester) async {
      for (final width in [400.0, 700.0]) {
        await pumpTimeline(tester, width);
        for (final node in editor.document.nodes) {
          final frames = node.tracks.single.keyframes;
          for (var index = 0; index < frames.length; index++) {
            final timeMs = node.motionTiming.delayMs + frames[index].timeMs;
            elapsed.value = Duration(milliseconds: timeMs);
            await tester.pumpAndSettle();
            final marker = find.byKey(ValueKey('keyframe-${node.id}-0-$index'));
            final markerX = tester.getCenter(marker).dx;
            expect(
              tester.getCenter(playhead).dx,
              closeTo(markerX, .1),
              reason: '${node.id} at ${timeMs}ms in a ${width}px timeline',
            );

            final scrubber = find.byKey(const ValueKey('timeline-scrubber'));
            await tester.tapAt(Offset(markerX, tester.getCenter(scrubber).dy));
            await tester.pumpAndSettle();
            expect(elapsed.value.inMicroseconds, closeTo(timeMs * 1000, 1000));
          }
        }
      }
      expect(editor.canUndo, isFalse);
      expect(editor.isDirty, isFalse);
    },
  );

  testWidgets(
    'dragging a keyframe to the playhead commits its displayed time',
    (tester) async {
      await pumpTimeline(tester, 700);
      elapsed.value = const Duration(milliseconds: 500);
      await tester.pumpAndSettle();
      final marker = find.byKey(const ValueKey('keyframe-plain-0-1'));
      final start = tester.getCenter(marker);
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(Offset(tester.getCenter(playhead).dx, start.dy));
      await tester.pump();
      expect(editor.selectedNode.tracks.single.keyframes[1].timeMs, 250);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(editor.selectedNode.tracks.single.keyframes[1].timeMs, 500);
      editor.undo();
      expect(editor.selectedNode.tracks.single.keyframes[1].timeMs, 250);
      expect(editor.canUndo, isFalse);
    },
  );
}
