import 'dart:convert';
import 'dart:io';

typedef FrameMetricSample = Map<String, double>;

const measuredInteractionPhases = [
  'background_motion',
  'wake',
  'account_picker_open',
  'account_select',
  'session_picker_open',
  'session_select',
  'credential_entry',
  'credential_submit',
];

const reportedPhases = [
  'startup',
  ...measuredInteractionPhases,
  'settled_idle',
];

double calculatePercentile(List<double> values, double percentile) {
  if (values.isEmpty) {
    return 0.0;
  }
  final sorted = values.toList()..sort();
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index];
}

double calculateMaximum(Iterable<double> values) {
  if (values.isEmpty) {
    return 0.0;
  }
  return values.reduce((left, right) => left > right ? left : right);
}

Future<Map<String, dynamic>> readPerfReport(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    throw ArgumentError('Report not found: $path');
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Report at $path is not a JSON object.');
  }
  return decoded;
}

num readRequiredNumber(Map<String, dynamic> map, String key) {
  final value = findOptionalNumber(map, key);
  if (value == null) {
    throw FormatException(
      'Report field $key must be a finite, non-negative number.',
    );
  }
  return value;
}

num? findOptionalNumber(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! num || !value.isFinite || value < 0) {
    return null;
  }
  return value;
}

/// Summarizes raw frames using rounded indices into sorted samples, without
/// interpolating timings. Empty input emits zero metrics alongside a zero sample
/// count; the gate must check that count rather than interpret zeros as success.
Map<String, Object?> summarizeFrameSamples(
  Iterable<FrameMetricSample> frames, {
  required double frameBudgetMs,
}) {
  final samples = frames.toList();
  double percentile(String key, double p) =>
      calculatePercentile(samples.map((s) => s[key]!).toList(), p);

  double maximum(String key) => calculateMaximum(samples.map((s) => s[key]!));

  int countOverBudget(String key) =>
      samples.where((sample) => sample[key]! > frameBudgetMs).length;

  return {
    'sample_count': samples.length,
    'frame_samples': samples,
    'p50_build_ms': percentile('build_ms', 0.50),
    'p95_build_ms': percentile('build_ms', 0.95),
    'p50_raster_ms': percentile('raster_ms', 0.50),
    'p95_raster_ms': percentile('raster_ms', 0.95),
    'p50_vsync_overhead_ms': percentile('vsync_overhead_ms', 0.50),
    'p95_vsync_overhead_ms': percentile('vsync_overhead_ms', 0.95),
    'p50_total_span_ms': percentile('total_span_ms', 0.50),
    'p95_total_span_ms': percentile('total_span_ms', 0.95),
    'max_build_ms': maximum('build_ms'),
    'max_raster_ms': maximum('raster_ms'),
    'max_total_span_ms': maximum('total_span_ms'),
    'build_over_budget_frame_count': countOverBudget('build_ms'),
    'raster_over_budget_frame_count': countOverBudget('raster_ms'),
    'total_over_budget_frame_count': countOverBudget('total_span_ms'),
  };
}
