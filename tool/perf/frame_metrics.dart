typedef FrameMetricSample = Map<String, double>;

const measuredInteractionPhases = [
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

Map<String, Object?> summarizeFrameSamples(
  Iterable<FrameMetricSample> frames, {
  required double frameBudgetMs,
}) {
  final samples = frames.toList();
  double percentile(String key, double percentile) {
    final values = samples.map((sample) => sample[key]!).toList()..sort();
    if (values.isEmpty) {
      return 0;
    }
    final index = ((values.length - 1) * percentile).round();
    return values[index];
  }

  double maximum(String key) {
    if (samples.isEmpty) {
      return 0;
    }
    return samples
        .map((sample) => sample[key]!)
        .reduce((left, right) => left > right ? left : right);
  }

  int countOverBudget(String key) {
    return samples.where((sample) => sample[key]! > frameBudgetMs).length;
  }

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
