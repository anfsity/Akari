import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show debugProfileLayoutsEnabled, debugProfilePaintsEnabled;
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mozais_greeter/main.dart';

import '../../tool/perf/frame_metrics.dart';

const _frameInterval = Duration(microseconds: 16667);
const _maxPhaseMatchDeltaMicros = 25000;
const _captureTimelineDiagnostics = bool.fromEnvironment(
  'MOZAIS_PERF_TRACE_TIMELINE',
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
    var engineEpochOffset = 0;
    var unmatchedFrameCount = 0;
    var timingFrameCount = 0;
    var maxPhaseMatchDeltaMicros = 0;
    var activePhase = 'startup';
    var captureFramePhases = true;
    var captureActionResponseFrame = false;
    void onFrame(Duration timestamp) {
      if (captureFramePhases) {
        final engineTimestamp =
            SchedulerBinding.instance.currentSystemFrameTimeStamp;
        // Scheduler frame times are epoch-adjusted; FrameTiming keeps engine time.
        engineEpochOffset =
            engineTimestamp.inMicroseconds - timestamp.inMicroseconds;
        phaseAtFrameStart[timestamp.inMicroseconds] = (
          phase: activePhase,
          actionResponse: captureActionResponseFrame,
        );
        captureActionResponseFrame = false;
      }
    }

    void onTimings(List<FrameTiming> batch) {
      for (final timing in batch) {
        timingFrameCount++;
        final vsyncStart = timing.timestampInMicroseconds(
          FramePhase.vsyncStart,
        );
        final adjustedVsyncStart = vsyncStart - engineEpochOffset;
        String? phase;
        var actionResponseFrame = false;
        var matchDeltaMicros = _maxPhaseMatchDeltaMicros + 1;
        // Linux timestamps can differ by about one display interval.
        for (final entry in phaseAtFrameStart.entries) {
          final delta = (entry.key - adjustedVsyncStart).abs();
          if (delta < matchDeltaMicros) {
            matchDeltaMicros = delta;
            phase = entry.value.phase;
            actionResponseFrame = entry.value.actionResponse;
          }
        }
        if (phase == null) {
          unmatchedFrameCount++;
          continue;
        }
        if (matchDeltaMicros > maxPhaseMatchDeltaMicros) {
          maxPhaseMatchDeltaMicros = matchDeltaMicros;
        }
        phaseTimings.putIfAbsent(phase, () => []).add(timing);
        if (measuredInteractionPhases.contains(phase)) {
          interactionTimings.add(timing);
        }
        if (actionResponseFrame) {
          actionResponseTimings[phase]?.add(timing);
        }
      }
    }

    Future<void> capturePhase(
      String phase,
      Future<void> Function() interaction,
    ) async {
      activePhase = phase;
      await interaction();
      captureActionResponseFrame = true;
      await tester.pump(_frameInterval);
      captureActionResponseFrame = false;
      await tester.pumpAndSettle(_frameInterval);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    Future<void> captureStartup() async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle(_frameInterval);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle(_frameInterval);
      await Future<void>.delayed(const Duration(milliseconds: 150));
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

    SchedulerBinding.instance.addPersistentFrameCallback(onFrame);
    SchedulerBinding.instance.addTimingsCallback(onTimings);

    if (_captureTimelineDiagnostics) {
      debugProfileBuildsEnabledUserWidgets = true;
      debugProfileLayoutsEnabled = true;
      debugProfilePaintsEnabled = true;
      try {
        final timeline = await binding.traceTimeline(() async {
          await tracePhase('MOZAIS_PERF.startup', captureStartup);
          await tracePhase('MOZAIS_PERF.wake', captureWake);
        });
        final traceFile = File('build/perf/scene_startup_wake_timeline.json');
        await traceFile.parent.create(recursive: true);
        await traceFile.writeAsString(jsonEncode(timeline.toJson()));
      } finally {
        debugProfileBuildsEnabledUserWidgets = false;
        debugProfileLayoutsEnabled = false;
        debugProfilePaintsEnabled = false;
      }
    } else {
      await captureStartup();
      await captureWake();
    }
    await capturePhase(
      'account_picker_open',
      () => tester.tap(find.byTooltip('Choose account')),
    );
    await capturePhase('account_select', () => tester.tap(find.text('Alice')));
    await capturePhase(
      'session_picker_open',
      () => tester.tap(find.byTooltip('Choose a session')),
    );
    await capturePhase('session_select', () => tester.tap(find.text('Sway')));
    await capturePhase(
      'credential_entry',
      () => tester.enterText(find.byType(TextField), 'secret'),
    );
    await capturePhase(
      'credential_submit',
      () => tester.tap(find.byIcon(Icons.arrow_forward)),
    );

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
        'unmatched_frame_count': unmatchedFrameCount,
        'matched_frame_count': timingFrameCount - unmatchedFrameCount,
        'max_delta_ms': maxPhaseMatchDeltaMicros / 1000,
      },
      'static_background_scheduled_frames': staticBackgroundFrames,
    };

    final output = File('build/perf/scene_report.json');
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
