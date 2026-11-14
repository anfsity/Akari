import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter_harness/greeter_harness.dart';
import 'package:greeter_harness/src/performance/aggregate_perf.dart'
    as aggregate;
import 'package:greeter_harness/src/performance/summarize_timeline.dart';

void main() {
  testWidgets('FrameTimingRecorder start/stop are idempotent and pre-seed phases', (
    tester,
  ) async {
    final recorder = FrameTimingRecorder(
      activePhase: 'startup',
      interactionPhases: const {'wake'},
    );
    addTearDown(recorder.stop);

    recorder.start();
    recorder.start();
    recorder.activePhase = 'wake';

    expect(recorder.phaseTimings.containsKey('startup'), isTrue);
    expect(recorder.phaseTimings.containsKey('wake'), isTrue);
    expect(recorder.actionResponseTimings.containsKey('wake'), isTrue);

    // In headless unit tests, engine frameNumber stays -1, so captureAction
    // completes with TimeoutException after frameTimeout without hanging.
    final pendingCapture = recorder.captureAction(
      'typing',
      () async {},
      frameTimeout: const Duration(milliseconds: 5),
    );
    final timeoutAssertion = expectLater(
      pendingCapture,
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(milliseconds: 10));
    await timeoutAssertion;
    expect(recorder.phaseTimings.containsKey('typing'), isTrue);

    await recorder.drain(timeout: const Duration(milliseconds: 10));
    recorder.stop();
    expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);

    await expectLater(
      recorder.captureAction('wake', () async {}),
      throwsStateError,
    );
  });

  test('readDartTimelineEvents closes nameless E events on the matching thread', () {
    final events = readDartTimelineEvents([
      {
        'cat': 'Dart',
        'pid': 1,
        'tid': 10,
        'ph': 'B',
        'name': 'BUILD',
        'ts': 1000,
      },
      {
        'cat': 'Dart',
        'pid': 1,
        'tid': 10,
        'ph': 'B',
        'name': 'ChildWidget',
        'ts': 1200,
      },
      {
        'cat': 'Dart',
        'pid': 1,
        'tid': 10,
        'ph': 'E',
        'ts': 1700,
      },
      {
        'cat': 'Dart',
        'pid': 1,
        'tid': 10,
        'ph': 'E',
        'ts': 2500,
      },
    ]);

    expect(events.map((e) => e.name).toList(), ['ChildWidget', 'BUILD']);
    expect(events.first.durationMs, closeTo(0.5, 0.001));
    expect(events.last.durationMs, closeTo(1.5, 0.001));
  });

  test('aggregate_perf rejects unmatched frames exceeding observed count', () async {
    final directory = await Directory.systemTemp.createTemp('akari-perf-neg-');
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/cycle.json');
    final output = File('${directory.path}/out.json');
    const sample = {
      'build_ms': 1.0,
      'raster_ms': 0.0,
      'vsync_overhead_ms': 0.0,
      'total_span_ms': 1.0,
    };
    const frames = {'frame_samples': [sample]};
    await input.writeAsString(
      jsonEncode({
        'frame_budget_ms': 16.667,
        'frame_samples': [sample],
        'observed_frame_count': 1,
        'phase_match': {
          'matching_method': 'frame_number',
          'unmatched_frame_count': 2,
        },
        'static_background_scheduled_frames': 0,
        'phases': {for (final phase in reportedPhases) phase: frames},
        'action_response_frames': {
          for (final phase in measuredInteractionPhases) phase: frames,
        },
      }),
    );

    await expectLater(
      aggregate.main(['--input', input.path, '--output', output.path]),
      throwsFormatException,
    );
  });

  testWidgets('runPreviewScenario rejects unknown scenarios explicitly', (
    tester,
  ) async {
    await expectLater(
      runPreviewScenario(
        tester,
        (_) => const SizedBox.shrink(),
        'nonexistent-scenario',
      ),
      throwsArgumentError,
    );
  });
}
