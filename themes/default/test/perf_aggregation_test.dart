import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../perf/aggregate_perf.dart' as aggregate;
import '../perf/frame_metrics.dart';

void main() {
  late Directory directory;
  late File input;
  late File output;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'akari-perf-aggregation-',
    );
    input = File('${directory.path}/cycle.json');
    output = File('${directory.path}/aggregate.json');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<void> aggregateReport(String source) async {
    await input.writeAsString(source);
    await aggregate.main(['--input', input.path, '--output', output.path]);
  }

  test('aggregates finite timings and accepts zero measurements', () async {
    await aggregateReport(jsonEncode(_getCycleReport()));

    final report = jsonDecode(await output.readAsString());
    expect(report['measurement_cycles'], 1);
    expect(report['sample_count'], 1);
    expect(report['p95_build_ms'], 1);
    expect(report['p95_raster_ms'], 0);
    expect(report['phase_match']['unmatched_frame_count'], 0);
  });

  for (final invalidTiming in ['-100.0', '1e309', '-1e309']) {
    test('rejects raw build timing $invalidTiming before publishing', () async {
      final source = jsonEncode(_getCycleReport())
          .replaceFirst('"build_ms":1.0', '"build_ms":$invalidTiming');

      await expectLater(
        aggregateReport(source),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('build_ms'),
          ),
        ),
      );
      expect(await output.exists(), isFalse);
    });
  }
}

Map<String, Object> _getCycleReport() {
  const sample = {
    'build_ms': 1.0,
    'raster_ms': 0.0,
    'vsync_overhead_ms': 0.0,
    'total_span_ms': 1.0,
  };
  const frames = {
    'frame_samples': [sample],
  };
  return {
    'frame_budget_ms': 16.667,
    'frame_samples': [sample],
    'observed_frame_count': 1,
    'phase_match': {
      'matching_method': 'frame_number',
      'unmatched_frame_count': 0,
    },
    'static_background_scheduled_frames': 0,
    'phases': {for (final phase in reportedPhases) phase: frames},
    'action_response_frames': {
      for (final phase in measuredInteractionPhases) phase: frames,
    },
  };
}
