import 'dart:convert';
import 'dart:io';

import 'frame_metrics.dart';

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  final reports = await Future.wait(options.inputs.map(readPerfReport));
  final frameBudget = readRequiredNumber(reports.first, 'frame_budget_ms');
  if (reports.any(
    (report) => readRequiredNumber(report, 'frame_budget_ms') != frameBudget,
  )) {
    throw const FormatException('All reports must use the same frame budget.');
  }

  // Pool raw samples and recompute percentiles. Averaging each cycle's p95
  // would give a different statistic and hide cycles with different sample counts.
  final interactionSamples = <FrameMetricSample>[];
  final phaseSamples = {
    for (final phase in reportedPhases) phase: <FrameMetricSample>[],
  };
  final actionResponseSamples = {
    for (final phase in measuredInteractionPhases) phase: <FrameMetricSample>[],
  };
  var observedFrameCount = 0;
  var unmatchedFrameCount = 0;
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
    final actionResponseFrames = report['action_response_frames'];
    if (actionResponseFrames is! Map<String, dynamic>) {
      throw const FormatException(
        'A report is missing action response frame data.',
      );
    }
    for (final phase in measuredInteractionPhases) {
      final phaseReport = actionResponseFrames[phase];
      if (phaseReport is! Map<String, dynamic>) {
        throw FormatException(
          'A report is missing $phase action response frame data.',
        );
      }
      actionResponseSamples[phase]!.addAll(
        _readFrameSamples(phaseReport, 'frame_samples', '$phase action'),
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
    // Keep cycle-level budget rates as well as pooled metrics: the gate needs
    // to distinguish a repeatable slowdown from one unusually noisy run.
    cycleSummaries.add({
      'cycle': cycle + 1,
      ...interactionSummary,
      'total_over_budget_frame_ratio':
          (interactionSummary['total_over_budget_frame_count'] as int) /
          sampleCount,
    });

    observedFrameCount += readRequiredNumber(report, 'observed_frame_count').toInt();
    final match = report['phase_match'];
    if (match is! Map<String, dynamic>) {
      throw const FormatException('A report is missing frame match data.');
    }
    if (match['matching_method'] != 'frame_number') {
      throw const FormatException(
        'A report does not use exact frame-number matching.',
      );
    }
    unmatchedFrameCount += readRequiredNumber(match, 'unmatched_frame_count').toInt();
    final staticFrames = readRequiredNumber(
      report,
      'static_background_scheduled_frames',
    );
    // Any cycle with continuing idle wake-ups matters. An average could conceal
    // a continuously animating background behind quieter measurements.
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
    'action_response_frames': {
      for (final entry in actionResponseSamples.entries)
        entry.key: summarizeFrameSamples(
          entry.value,
          frameBudgetMs: frameBudget.toDouble(),
        ),
    },
    'phase_match': {
      'matching_method': 'frame_number',
      'unmatched_frame_count': unmatchedFrameCount,
      'matched_frame_count': observedFrameCount - unmatchedFrameCount,
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
          'build_ms': readRequiredNumber(sample, 'build_ms').toDouble(),
          'raster_ms': readRequiredNumber(sample, 'raster_ms').toDouble(),
          'vsync_overhead_ms': readRequiredNumber(
            sample,
            'vsync_overhead_ms',
          ).toDouble(),
          'total_span_ms': readRequiredNumber(sample, 'total_span_ms').toDouble(),
        }
      else
        throw FormatException('$label contains an invalid frame sample.'),
  ];
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
