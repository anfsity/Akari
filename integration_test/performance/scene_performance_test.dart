import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mozais_greeter/main.dart';

const _frameInterval = Duration(microseconds: 16667);
const _maxPhaseMatchDeltaMicros = 25000;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures scene interaction frame timings', (tester) async {
    final interactionTimings = <FrameTiming>[];
    final phaseTimings = <String, List<FrameTiming>>{'startup': []};
    final phaseAtFrameStart = <int, String>{};
    var engineEpochOffset = 0;
    var unmatchedFrameCount = 0;
    var maxPhaseMatchDeltaMicros = 0;
    var activePhase = 'startup';
    var captureFramePhases = true;
    void onFrame(Duration timestamp) {
      if (captureFramePhases) {
        final engineTimestamp =
            SchedulerBinding.instance.currentSystemFrameTimeStamp;
        // Scheduler frame times are epoch-adjusted; FrameTiming keeps engine time.
        engineEpochOffset =
            engineTimestamp.inMicroseconds - timestamp.inMicroseconds;
        phaseAtFrameStart[timestamp.inMicroseconds] = activePhase;
      }
    }

    void onTimings(List<FrameTiming> batch) {
      for (final timing in batch) {
        final buildStart = timing.timestampInMicroseconds(
          FramePhase.buildStart,
        );
        final adjustedBuildStart = buildStart - engineEpochOffset;
        String? phase;
        var matchDeltaMicros = _maxPhaseMatchDeltaMicros + 1;
        // Linux timestamps can differ by about one display interval.
        for (final entry in phaseAtFrameStart.entries) {
          final delta = (entry.key - adjustedBuildStart).abs();
          if (delta < matchDeltaMicros) {
            matchDeltaMicros = delta;
            phase = entry.value;
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
        if (phase != 'startup' && phase != 'settled_idle') {
          interactionTimings.add(timing);
        }
      }
    }

    Future<void> capturePhase(
      String phase,
      Future<void> Function() interaction,
    ) async {
      activePhase = phase;
      await interaction();
      await tester.pumpAndSettle(_frameInterval);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    SchedulerBinding.instance.addPersistentFrameCallback(onFrame);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle(_frameInterval);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(_frameInterval);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    await capturePhase('wake', () => tester.tapAt(const Offset(10, 10)));
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
      ..._summarize(interactionTimings),
      'phases': {
        for (final entry in phaseTimings.entries)
          entry.key: _summarize(entry.value),
      },
      'phase_match': {
        'unmatched_frame_count': unmatchedFrameCount,
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
  final samples = frames.toList();
  double percentile(
    Duration Function(FrameTiming) duration,
    double percentile,
  ) {
    return _percentile(
      samples.map((timing) => duration(timing).inMicroseconds / 1000),
      percentile,
    );
  }

  return {
    'sample_count': samples.length,
    'p50_build_ms': percentile((timing) => timing.buildDuration, 0.50),
    'p95_build_ms': percentile((timing) => timing.buildDuration, 0.95),
    'p50_raster_ms': percentile((timing) => timing.rasterDuration, 0.50),
    'p95_raster_ms': percentile((timing) => timing.rasterDuration, 0.95),
    'p50_vsync_overhead_ms': percentile((timing) => timing.vsyncOverhead, 0.50),
    'p95_vsync_overhead_ms': percentile((timing) => timing.vsyncOverhead, 0.95),
    'p50_total_span_ms': percentile((timing) => timing.totalSpan, 0.50),
    'p95_total_span_ms': percentile((timing) => timing.totalSpan, 0.95),
  };
}

double _percentile(Iterable<double> values, double percentile) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) {
    return 0;
  }
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index];
}
