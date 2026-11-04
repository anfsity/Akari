import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show debugProfileLayoutsEnabled, debugProfilePaintsEnabled;
import 'package:flutter_test/flutter_test.dart';

import 'package:greeter/app/app.dart';

import 'package:theme_default/theme.dart';

import 'package:greeter_harness/greeter_harness.dart';

const _frameInterval = Duration(microseconds: 16667);
const _captureTimelineDiagnostics = bool.fromEnvironment(
  'AKARI_PERF_TRACE_TIMELINE',
);
const _timelinePath = String.fromEnvironment(
  'AKARI_PERF_TIMELINE_PATH',
  defaultValue: 'build/perf/scene_interactions_timeline.json',
);
const _reportPath = String.fromEnvironment(
  'AKARI_PERF_REPORT_PATH',
  defaultValue: 'build/perf/scene_report.json',
);

void main() {
  final binding = PerformanceTestBinding();

  testWidgets('captures scene interaction frame timings', (tester) async {
    final recorder = FrameTimingRecorder(
      activePhase: 'startup',
      interactionPhases: measuredInteractionPhases.toSet(),
    )..start();
    addTearDown(recorder.stop);

    Future<void> capturePhase(
      String phase,
      Future<void> Function() interaction,
    ) async {
      await recorder.captureAction(phase, interaction);
      await tester.pumpAndSettle(_frameInterval);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    Future<void> captureStartup() async {
      await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
      await tester.pumpAndSettle(_frameInterval);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle(_frameInterval);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    }

    Future<void> tracePhase(String name, Future<void> Function() action) async {
      developer.Timeline.startSync(name);
      try {
        await action();
      } finally {
        developer.Timeline.finishSync();
      }
    }

    Future<void> captureNamedPhase(
      String name,
      Future<void> Function() action,
    ) {
      if (!_captureTimelineDiagnostics) {
        return action();
      }
      return tracePhase('AKARI_PERF.$name', action);
    }

    Future<void> runPhase(String phase, Future<void> Function() action) =>
        captureNamedPhase(phase, () => capturePhase(phase, action));

    Future<void> captureJourney() async {
      await captureNamedPhase('startup', captureStartup);
      final sceneSize = tester.getSize(find.byType(MyApp));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: sceneSize.center(Offset.zero));
      addTearDown(mouse.removePointer);
      await tester.pumpAndSettle(_frameInterval);
      await runPhase(
        'background_motion',
        () => mouse.moveTo(
          Offset(sceneSize.width * 0.65, sceneSize.height * 0.2),
        ),
      );
      await runPhase('wake', () => tester.tapAt(const Offset(10, 10)));
      await runPhase(
        'account_picker_open',
        () => tester.tap(find.byTooltip('Choose account')),
      );
      await runPhase(
        'account_select',
        () => tester.tap(find.text('Alice')),
      );
      await runPhase(
        'session_picker_open',
        () => tester.tap(find.byTooltip('Choose a session')),
      );
      await runPhase(
        'session_select',
        () => tester.tap(find.text('Sway')),
      );
      await runPhase(
        'credential_entry',
        () => tester.enterText(find.byType(TextField), 'secret'),
      );
      await runPhase(
        'credential_submit',
        () => tester.tap(find.byIcon(Icons.arrow_forward)),
      );
    }

    if (_captureTimelineDiagnostics) {
      // Widget/layout/paint instrumentation adds overhead. Enable it only for
      // the separate diagnostic trace, not normal performance gate measurements.
      debugProfileBuildsEnabledUserWidgets = true;
      debugProfileLayoutsEnabled = true;
      debugProfilePaintsEnabled = true;
      try {
        final timeline = await binding.traceTimeline(captureJourney);
        final traceFile = File(_timelinePath);
        await traceFile.parent.create(recursive: true);
        await traceFile.writeAsString(jsonEncode(timeline.toJson()));
      } finally {
        debugProfileBuildsEnabledUserWidgets = false;
        debugProfileLayoutsEnabled = false;
        debugProfilePaintsEnabled = false;
      }
    } else {
      await captureJourney();
    }

    recorder.activePhase = 'settled_idle';
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(_frameInterval);
    final settledIdleFrames = recorder.phaseTimings['settled_idle']?.length ?? 0;
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    final staticBackgroundFrames =
        (recorder.phaseTimings['settled_idle']?.length ?? 0) - settledIdleFrames;

    recorder.stop();

    final report = <String, Object?>{
      'frame_budget_ms': _frameInterval.inMicroseconds / 1000,
      'observed_frame_count': recorder.observedFrameCount,
      ..._summarize(recorder.interactionTimings),
      'phases': {
        for (final phase in reportedPhases)
          phase: _summarize(recorder.phaseTimings[phase] ?? const <FrameTiming>[]),
      },
      'action_response_frames': {
        for (final phase in measuredInteractionPhases)
          phase: _summarize(recorder.actionResponseTimings[phase] ?? const <FrameTiming>[]),
      },
      'phase_match': {
        'matching_method': 'frame_number',
        'unmatched_frame_count': recorder.unmatchedFrameCount,
        'matched_frame_count': recorder.observedFrameCount - recorder.unmatchedFrameCount,
      },
      'static_background_scheduled_frames': staticBackgroundFrames,
    };

    final output = File(_reportPath);
    await output.parent.create(recursive: true);
    await output.writeAsString(jsonEncode(report));
    binding.reportData = report;
  });
}

Map<String, Object?> _summarize(Iterable<FrameTiming> frames) {
  final samples = frames
      .map(
        (timing) => <String, double>{
          'build_ms': timing.buildDuration.inMicroseconds / 1000,
          'raster_ms': timing.rasterDuration.inMicroseconds / 1000,
          'vsync_overhead_ms': timing.vsyncOverhead.inMicroseconds / 1000,
          'total_span_ms': timing.totalSpan.inMicroseconds / 1000,
        },
      )
      .toList();
  return summarizeFrameSamples(
    samples,
    frameBudgetMs: _frameInterval.inMicroseconds / 1000,
  );
}
