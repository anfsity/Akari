import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show debugProfileLayoutsEnabled, debugProfilePaintsEnabled;
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mozais_greeter/main.dart';

import '../../tool/perf/frame_metrics.dart';

const _frameInterval = Duration(microseconds: 16667);
const _captureTimelineDiagnostics = bool.fromEnvironment(
  'MOZAIS_PERF_TRACE_TIMELINE',
);
const _timelinePath = String.fromEnvironment(
  'MOZAIS_PERF_TIMELINE_PATH',
  defaultValue: 'build/perf/scene_interactions_timeline.json',
);
const _reportPath = String.fromEnvironment(
  'MOZAIS_PERF_REPORT_PATH',
  defaultValue: 'build/perf/scene_report.json',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures scene interaction frame timings', (tester) async {
    final interactionTimings = <FrameTiming>[];
    final phaseTimings = <String, List<FrameTiming>>{'startup': []};
    final phaseAtFrameStart = <int, ({String phase, bool actionResponse})>{};
    final actionResponseTimings = {
      for (final phase in measuredInteractionPhases) phase: <FrameTiming>[],
    };
    var unmatchedFrameCount = 0;
    var timingFrameCount = 0;
    var activePhase = 'startup';
    var captureFramePhases = true;
    var captureActionResponseFrame = false;
    void onFrame(Duration _) {
      if (captureFramePhases) {
        final frameNumber = PlatformDispatcher.instance.frameData.frameNumber;
        if (frameNumber < 0) {
          return;
        }
        phaseAtFrameStart[frameNumber] = (
          phase: activePhase,
          actionResponse: captureActionResponseFrame,
        );
        captureActionResponseFrame = false;
      }
    }

    void onTimings(List<FrameTiming> batch) {
      for (final timing in batch) {
        timingFrameCount++;
        final frame = timing.frameNumber < 0
            ? null
            : phaseAtFrameStart.remove(timing.frameNumber);
        if (frame == null) {
          unmatchedFrameCount++;
          continue;
        }
        final phase = frame.phase;
        phaseTimings.putIfAbsent(phase, () => []).add(timing);
        if (measuredInteractionPhases.contains(phase)) {
          interactionTimings.add(timing);
        }
        if (frame.actionResponse) {
          actionResponseTimings[phase]?.add(timing);
        }
      }
    }

    Future<void> capturePhase(
      String phase,
      Future<void> Function() interaction,
    ) async {
      activePhase = phase;
      captureActionResponseFrame = true;
      try {
        await interaction();
        await tester.pump(_frameInterval);
      } finally {
        captureActionResponseFrame = false;
      }
      await tester.pumpAndSettle(_frameInterval);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    Future<void> captureStartup() async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle(_frameInterval);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle(_frameInterval);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    }

    Future<void> captureWake() =>
        capturePhase('wake', () => tester.tapAt(const Offset(10, 10)));

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
      return tracePhase('MOZAIS_PERF.$name', action);
    }

    Future<void> captureJourney() async {
      await captureNamedPhase('startup', captureStartup);
      await captureNamedPhase('wake', captureWake);
      await captureNamedPhase(
        'account_picker_open',
        () => capturePhase(
          'account_picker_open',
          () => tester.tap(find.byTooltip('Choose account')),
        ),
      );
      await captureNamedPhase(
        'account_select',
        () => capturePhase(
          'account_select',
          () => tester.tap(find.text('Alice')),
        ),
      );
      await captureNamedPhase(
        'session_picker_open',
        () => capturePhase(
          'session_picker_open',
          () => tester.tap(find.byTooltip('Choose a session')),
        ),
      );
      await captureNamedPhase(
        'session_select',
        () =>
            capturePhase('session_select', () => tester.tap(find.text('Sway'))),
      );
      await captureNamedPhase(
        'credential_entry',
        () => capturePhase(
          'credential_entry',
          () => tester.enterText(find.byType(TextField), 'secret'),
        ),
      );
      await captureNamedPhase(
        'credential_submit',
        () => capturePhase(
          'credential_submit',
          () => tester.tap(find.byIcon(Icons.arrow_forward)),
        ),
      );
    }

    SchedulerBinding.instance.addPersistentFrameCallback(onFrame);
    SchedulerBinding.instance.addTimingsCallback(onTimings);

    if (_captureTimelineDiagnostics) {
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

    activePhase = 'settled_idle';
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(_frameInterval);
    final settledIdleFrames = phaseTimings['settled_idle']?.length ?? 0;
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    final staticBackgroundFrames =
        (phaseTimings['settled_idle']?.length ?? 0) - settledIdleFrames;

    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    captureFramePhases = false;
    phaseAtFrameStart.clear();

    final report = <String, Object?>{
      'frame_budget_ms': _frameInterval.inMicroseconds / 1000,
      'observed_frame_count': timingFrameCount,
      ..._summarize(interactionTimings),
      'phases': {
        for (final phase in reportedPhases)
          phase: _summarize(phaseTimings[phase] ?? const <FrameTiming>[]),
      },
      'action_response_frames': {
        for (final phase in measuredInteractionPhases)
          phase: _summarize(actionResponseTimings[phase]!),
      },
      'phase_match': {
        'matching_method': 'frame_number',
        'unmatched_frame_count': unmatchedFrameCount,
        'matched_frame_count': timingFrameCount - unmatchedFrameCount,
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
