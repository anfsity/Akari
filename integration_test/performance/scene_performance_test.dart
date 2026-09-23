import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mozais_greeter/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures scene interaction frame timings', (tester) async {
    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> batch) => timings.addAll(batch);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    SchedulerBinding.instance.addTimingsCallback(onTimings);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Choose account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Choose a session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sway'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final settledFrameCount = timings.length;
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    final staticBackgroundFrames = timings.length - settledFrameCount;

    SchedulerBinding.instance.removeTimingsCallback(onTimings);

    final measuredTimings = timings.length > 5 ? timings.sublist(5) : timings;
    final report = <String, Object?>{
      'p50_build_ms': _percentile(
        measuredTimings.map(
          (timing) => timing.buildDuration.inMicroseconds / 1000,
        ),
        0.50,
      ),
      'p95_build_ms': _percentile(
        measuredTimings.map(
          (timing) => timing.buildDuration.inMicroseconds / 1000,
        ),
        0.95,
      ),
      'p50_raster_ms': _percentile(
        measuredTimings.map(
          (timing) => timing.rasterDuration.inMicroseconds / 1000,
        ),
        0.50,
      ),
      'p95_raster_ms': _percentile(
        measuredTimings.map(
          (timing) => timing.rasterDuration.inMicroseconds / 1000,
        ),
        0.95,
      ),
      'static_background_scheduled_frames': staticBackgroundFrames,
      'sample_count': measuredTimings.length,
    };

    final output = File('build/perf/scene_report.json');
    await output.parent.create(recursive: true);
    await output.writeAsString(jsonEncode(report));
    binding.reportData = report;
  });
}

double _percentile(Iterable<double> values, double percentile) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) {
    return 0;
  }
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index];
}
