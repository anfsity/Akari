import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming, PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter/app/app.dart';
import 'package:integration_test/integration_test.dart';
import 'package:theme_preset1/theme.dart';

const _output = String.fromEnvironment('PRESET1_PERF_OUTPUT');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  testWidgets('measures animated environment and dispersed login in Sway', (
    tester,
  ) async {
    final phases = <String, List<FrameTiming>>{};
    final framePhases = <int, String>{};
    var phase = 'warmup';
    var collecting = true;
    void onFrame(Duration _) {
      if (collecting) {
        framePhases[PlatformDispatcher.instance.frameData.frameNumber] = phase;
      }
    }

    void onTimings(List<FrameTiming> timings) {
      for (final timing in timings) {
        final captured = framePhases.remove(timing.frameNumber);
        if (captured != null && captured != 'warmup') {
          phases.putIfAbsent(captured, () => []).add(timing);
        }
      }
    }

    SchedulerBinding.instance.addPersistentFrameCallback(onFrame);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    addTearDown(() {
      collecting = false;
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
    });

    Future<void> wait([int milliseconds = 1400]) =>
        Future<void>.delayed(Duration(milliseconds: milliseconds));
    Future<void> capture(String name) async {
      final result = await Process.run('grim', ['$_output/$name.png']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    Future<void> sendKey(String key) async {
      final result = await Process.run('wtype', ['-k', key]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    await tester.pumpWidget(MyApp(themeBuilder: buildPreset1Theme));
    await wait(2500);
    for (var cycle = 0; cycle < 3; cycle++) {
      phase = 'dormant';
      await wait(2500);
      if (cycle == 0) {
        await capture('dormant');
        await wait(500);
        await capture('dormant_rain');
      }
      phase = 'wake';
      await sendKey('space');
      await wait();
      if (cycle == 0) {
        await tester.tap(find.byTooltip('Choose account'));
        await wait(500);
        await capture('account_menu');
        await tester.tap(find.text('Alice').last);
        await wait(500);
      }
      phase = 'typing';
      await tester.tap(find.byType(TextField));
      for (final character in 'secret'.split('')) {
        final result = await Process.run('wtype', [character]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        await wait(150);
      }
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'secret',
      );
      await wait();
      if (cycle == 0) await capture('login');
      phase = 'session_menu';
      await tester.tap(find.byTooltip('Choose a session'));
      await wait();
      if (cycle == 0) await capture('session_menu');
      await sendKey('Escape');
      await wait(500);
      phase = 'error';
      await tester.tap(find.byType(TextField));
      await wait(200);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      await sendKey('End');
      for (var i = 0; i < 6; i++) {
        await sendKey('BackSpace');
        await wait(50);
      }
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await sendKey('Return');
      await wait();
      expect(find.byIcon(Icons.refresh).hitTestable(), findsOneWidget);
      if (cycle == 0) await capture('error');
      phase = 'recovery';
      await tester.tap(find.byIcon(Icons.refresh));
      await wait();
      await sendKey('Escape');
      await wait();
    }
    phase = 'warmup';
    await wait(1500); // Drain delayed engine timing batches before summarizing.
    final summaries = {
      for (final entry in phases.entries) entry.key: _getSummary(entry.value),
    };
    final view = PlatformDispatcher.instance.implicitView!;
    final report = {
      'cycles': 3,
      'frame_budget_ms': 16.667,
      'physical_size': [view.physicalSize.width, view.physicalSize.height],
      'device_pixel_ratio': view.devicePixelRatio,
      'phases': summaries,
    };
    await File('$_output/report.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    binding.reportData = report;
    for (final name in [
      'dormant',
      'wake',
      'typing',
      'session_menu',
      'error',
      'recovery',
    ]) {
      final summary = summaries[name]!;
      expect(
        summary['frames'],
        greaterThanOrEqualTo(90),
        reason: '$name sample count',
      );
      expect(
        summary['build_p95_ms'],
        lessThan(8),
        reason: '$name UI thread budget',
      );
      expect(
        summary['raster_p95_ms'],
        lessThan(12),
        reason: '$name raster thread budget',
      );
      expect(
        summary['total_p95_ms'],
        lessThan(33.334),
        reason: '$name frame latency',
      );
      expect(
        summary['frame_interval_p95_ms'],
        lessThan(25),
        reason: '$name sustained frame cadence',
      );
      expect(
        summary['over_budget_fraction'],
        lessThan(.20),
        reason: '$name missed frame budget',
      );
    }
    await tester.pumpWidget(const SizedBox());
  });
}

Map<String, num> _getSummary(List<FrameTiming> timings) {
  double percentile(Iterable<Duration> values) {
    final sorted = values.map((d) => d.inMicroseconds / 1000).toList()..sort();
    return sorted[((sorted.length - 1) * .95).round()];
  }

  final intervals = <Duration>[
    for (var i = 1; i < timings.length; i++)
      if (timings[i].frameNumber == timings[i - 1].frameNumber + 1)
        Duration(
          microseconds:
              timings[i].timestampInMicroseconds(FramePhase.vsyncStart) -
              timings[i - 1].timestampInMicroseconds(FramePhase.vsyncStart),
        ),
  ];

  return {
    'frames': timings.length,
    'frame_interval_p95_ms': percentile(intervals),
    'build_p95_ms': percentile(timings.map((t) => t.buildDuration)),
    'raster_p95_ms': percentile(timings.map((t) => t.rasterDuration)),
    'total_p95_ms': percentile(timings.map((t) => t.totalSpan)),
    'over_budget_fraction':
        timings.where((t) => t.totalSpan.inMicroseconds > 16667).length /
        timings.length,
  };
}
