import 'dart:convert';
import 'dart:io';

import 'frame_metrics.dart';

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  final reports = await Future.wait(options.inputs.map(_readReport));
  final frameBudget = _readNumber(reports.first, 'frame_budget_ms');
  if (reports.any(
    (report) => _readNumber(report, 'frame_budget_ms') != frameBudget,
  )) {
    throw const FormatException('All reports must use the same frame budget.');
  }

  final interactionSamples = <FrameMetricSample>[];
  final phaseSamples = {
    for (final phase in reportedPhases) phase: <FrameMetricSample>[],
  };
  var observedFrameCount = 0;
  var unmatchedFrameCount = 0;
  var maxPhaseMatchDeltaMs = 0.0;
  var staticBackgroundFrames = 0.0;
  final cycleSummaries = <Map<String, Object?>>[];

  for (var cycle = 0; cycle < reports.length; cycle++) {
    final report = reports[cycle];
    interactionSamples.addAll(
      _readFrameSamples(report, 'frame_samples', 'interaction'),
    );
    final phases = report['phases'];
    if (phases is! Map<String, dynamic>) {
      throw const FormatException('A report is missing phase data.');
    }
    for (final phase in reportedPhases) {
      final phaseReport = phases[phase];
      if (phaseReport is! Map<String, dynamic>) {
        throw FormatException('A report is missing the $phase phase.');
      }
      phaseSamples[phase]!.addAll(
        _readFrameSamples(phaseReport, 'frame_samples', phase),
      );
    }

    final interactionSummary = summarizeFrameSamples(
      _readFrameSamples(report, 'frame_samples', 'interaction'),
      frameBudgetMs: frameBudget.toDouble(),
    )..remove('frame_samples');
    final sampleCount = interactionSummary['sample_count'] as int;
    if (sampleCount == 0) {
      throw FormatException('Cycle ${cycle + 1} has no interaction frames.');
    }
    cycleSummaries.add({
      'cycle': cycle + 1,
      ...interactionSummary,
      'total_over_budget_frame_ratio':
          (interactionSummary['total_over_budget_frame_count'] as int) /
          sampleCount,
    });

    observedFrameCount += _readNumber(report, 'observed_frame_count').toInt();
    final match = report['phase_match'];
    if (match is! Map<String, dynamic>) {
      throw const FormatException('A report is missing frame match data.');
    }
    unmatchedFrameCount += _readNumber(match, 'unmatched_frame_count').toInt();
    final delta = _readNumber(match, 'max_delta_ms');
    if (delta > maxPhaseMatchDeltaMs) {
      maxPhaseMatchDeltaMs = delta.toDouble();
    }
    final staticFrames = _readNumber(
      report,
      'static_background_scheduled_frames',
    );
    if (staticFrames > staticBackgroundFrames) {
      staticBackgroundFrames = staticFrames.toDouble();
    }
  }

  final report = <String, Object?>{
    'measurement_cycles': reports.length,
    'cycles': cycleSummaries,
    'frame_budget_ms': frameBudget,
    'observed_frame_count': observedFrameCount,
    ...summarizeFrameSamples(
      interactionSamples,
      frameBudgetMs: frameBudget.toDouble(),
    ),
    'phases': {
      for (final entry in phaseSamples.entries)
        entry.key: summarizeFrameSamples(
          entry.value,
          frameBudgetMs: frameBudget.toDouble(),
        ),
    },
    'phase_match': {
      'unmatched_frame_count': unmatchedFrameCount,
      'matched_frame_count': observedFrameCount - unmatchedFrameCount,
      'max_delta_ms': maxPhaseMatchDeltaMs,
    },
    'static_background_scheduled_frames': staticBackgroundFrames,
  };

  final output = File(options.output);
  await output.parent.create(recursive: true);
  await output.writeAsString(jsonEncode(report));
}

List<FrameMetricSample> _readFrameSamples(
  Map<String, dynamic> report,
  String key,
  String label,
) {
  final value = report[key];
  if (value is! List) {
    throw FormatException('$label is missing raw frame samples.');
  }
  return [
    for (final sample in value)
      if (sample is Map<String, dynamic>)
        {
          'build_ms': _readNumber(sample, 'build_ms').toDouble(),
          'raster_ms': _readNumber(sample, 'raster_ms').toDouble(),
          'vsync_overhead_ms': _readNumber(
            sample,
            'vsync_overhead_ms',
          ).toDouble(),
          'total_span_ms': _readNumber(sample, 'total_span_ms').toDouble(),
        }
      else
        throw FormatException('$label contains an invalid frame sample.'),
  ];
}

num _readNumber(Map<String, dynamic> report, String key) {
  final value = report[key];
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('Report field $key must be a non-negative number.');
  }
  return value;
}

Future<Map<String, dynamic>> _readReport(String path) async {
  final decoded = jsonDecode(await File(path).readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('$path must contain a JSON object.');
  }
  return decoded;
}

({List<String> inputs, String output}) _parseArguments(List<String> arguments) {
  final inputs = <String>[];
  String? output;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument != '--input' && argument != '--output') {
      throw ArgumentError('Unexpected argument: $argument');
    }
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      throw ArgumentError('Missing value for $argument.');
    }
    final value = arguments[++index];
    if (argument == '--input') {
      inputs.add(value);
    } else if (output != null) {
      throw ArgumentError('Duplicate --output option.');
    } else {
      output = value;
    }
  }
  if (inputs.isEmpty) {
    throw ArgumentError('At least one --input is required.');
  }
  if (output == null) {
    throw ArgumentError('Missing --output.');
  }
  return (inputs: inputs, output: output);
}
