import 'dart:convert';
import 'dart:io';

import 'frame_metrics.dart';

const _regressionThreshold = 1.20;
const _maximumUnmatchedFrameRatio = 0.20;
const _maximumOverBudgetCycleRatio = 0.20;
const _minimumSamplesPerPhase = 5;
const _minimumMeasurementCycles = 3;
const _maximumActionResponseBuildMs = 5.0;

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  final baseline = await _readReport(options['baseline']!);
  final candidate = await _readReport(options['candidate']!);

  final failures = <String>[];
  final measurementCycles = _readNumber(candidate, 'measurement_cycles');
  if (measurementCycles == null ||
      measurementCycles < _minimumMeasurementCycles) {
    failures.add(
      'candidate has fewer than $_minimumMeasurementCycles measurement cycles',
    );
  }

  final sampleCount = _readNumber(candidate, 'sample_count');
  if (sampleCount == null || sampleCount < 1) {
    failures.add('candidate has no interaction frame samples');
  }

  final overBudgetFrameCount = _readNumber(
    candidate,
    'total_over_budget_frame_count',
  );
  if (sampleCount != null && sampleCount > 0 && overBudgetFrameCount != null) {
    final overBudgetRatio = overBudgetFrameCount / sampleCount;
    final cycles = candidate['cycles'];
    if (cycles is! List || cycles.length < _minimumMeasurementCycles) {
      failures.add('candidate is missing per-cycle frame budget data');
    } else {
      var cyclesOverLimit = 0;
      for (var index = 0; index < cycles.length; index++) {
        final cycle = cycles[index];
        if (cycle is! Map<String, dynamic>) {
          failures.add('cycle ${index + 1} has invalid frame budget data');
          continue;
        }
        final cycleRatio = _readNumber(cycle, 'total_over_budget_frame_ratio');
        if (cycleRatio == null) {
          failures.add('cycle ${index + 1} is missing frame budget data');
        } else if (cycleRatio > _maximumOverBudgetCycleRatio) {
          cyclesOverLimit++;
        }
      }
      if (measurementCycles != null && cycles.length != measurementCycles) {
        failures.add('candidate cycle count does not match measurement count');
      }
      final requiredCycles = cycles.length ~/ 2 + 1;
      if (cyclesOverLimit >= requiredCycles) {
        failures.add(
          '$cyclesOverLimit of ${cycles.length} cycles had more than '
          '${(_maximumOverBudgetCycleRatio * 100).round()}% of interaction '
          'frames over the ${_readNumber(candidate, 'frame_budget_ms')?.toStringAsFixed(2) ?? 'unknown'} ms budget',
        );
      }
      stdout.writeln(
        'Cycles over the '
        '${(_maximumOverBudgetCycleRatio * 100).round()}% frame budget rate: '
        '$cyclesOverLimit/${cycles.length}',
      );
    }
    stdout.writeln(
      'Interaction frames over budget: '
      '${overBudgetFrameCount.toInt()}/${sampleCount.toInt()} '
      '(${(overBudgetRatio * 100).toStringAsFixed(1)}%)',
    );
  } else {
    failures.add('candidate is missing total over-budget frame count');
  }

  final frameBudget = _readNumber(candidate, 'frame_budget_ms');
  final p95TotalSpan = _readNumber(candidate, 'p95_total_span_ms');
  if (frameBudget == null || frameBudget == 0 || p95TotalSpan == null) {
    failures.add('candidate is missing frame budget or total span data');
  } else if (p95TotalSpan > frameBudget * 2) {
    failures.add(
      'interaction p95 total span is ${p95TotalSpan.toStringAsFixed(2)} ms; '
      'limit is ${(frameBudget * 2).toStringAsFixed(2)} ms',
    );
  }

  final staticBackgroundFrames = _readNumber(
    candidate,
    'static_background_scheduled_frames',
  );
  if (staticBackgroundFrames == null) {
    failures.add('candidate is missing static background frame data');
  } else if (staticBackgroundFrames > 1) {
    failures.add('static background scheduled continuous frames after settle');
  }

  final phases = candidate['phases'];
  if (phases is! Map<String, dynamic>) {
    failures.add('candidate is missing per-phase frame data');
  } else {
    for (final phaseName in measuredInteractionPhases) {
      final phase = phases[phaseName];
      if (phase is! Map<String, dynamic>) {
        failures.add('$phaseName is missing frame data');
        continue;
      }
      final phaseSamples = _readNumber(phase, 'sample_count');
      if (phaseSamples == null || phaseSamples < _minimumSamplesPerPhase) {
        failures.add(
          '$phaseName has fewer than $_minimumSamplesPerPhase matched frames',
        );
      } else if (frameBudget != null && frameBudget > 0) {
        final phaseP95TotalSpan = _readNumber(phase, 'p95_total_span_ms');
        if (phaseP95TotalSpan == null) {
          failures.add('$phaseName is missing p95 total span data');
        } else if (phaseP95TotalSpan > frameBudget * 2) {
          failures.add(
            '$phaseName p95 total span is '
            '${phaseP95TotalSpan.toStringAsFixed(2)} ms; '
            'limit is ${(frameBudget * 2).toStringAsFixed(2)} ms',
          );
        }
      }
    }
    _printPhaseSummary(phases);
  }

  final actionResponseFrames = candidate['action_response_frames'];
  if (actionResponseFrames is! Map<String, dynamic>) {
    failures.add('candidate is missing action response frame data');
  } else {
    for (final phaseName in measuredInteractionPhases) {
      final phase = actionResponseFrames[phaseName];
      if (phase is! Map<String, dynamic>) {
        failures.add('$phaseName is missing action response frame data');
        continue;
      }
      final actionFrameCount = _readNumber(phase, 'sample_count');
      if (actionFrameCount == null ||
          measurementCycles == null ||
          actionFrameCount < measurementCycles) {
        failures.add(
          '$phaseName has fewer action response frames than measurement cycles',
        );
        continue;
      }
      final maxBuildMs = _readNumber(phase, 'max_build_ms');
      if (maxBuildMs == null) {
        failures.add('$phaseName is missing action response build timing');
      } else if (maxBuildMs >= _maximumActionResponseBuildMs) {
        failures.add(
          '$phaseName action response frame build reached '
          '${maxBuildMs.toStringAsFixed(2)} ms; limit is below '
          '$_maximumActionResponseBuildMs ms',
        );
      }
    }
    _printActionResponseSummary(actionResponseFrames);
  }

  final observedFrameCount = _readNumber(candidate, 'observed_frame_count');
  final phaseMatch = candidate['phase_match'];
  if (observedFrameCount == null ||
      observedFrameCount < 1 ||
      phaseMatch is! Map<String, dynamic>) {
    failures.add('candidate is missing observed frame phase match data');
  } else {
    if (phaseMatch['matching_method'] != 'frame_number') {
      failures.add('candidate does not use exact frame-number matching');
    }
    final unmatchedFrameCount = _readNumber(
      phaseMatch,
      'unmatched_frame_count',
    );
    if (unmatchedFrameCount == null) {
      failures.add('candidate is missing unmatched frame count');
    } else if (unmatchedFrameCount / observedFrameCount >
        _maximumUnmatchedFrameRatio) {
      failures.add(
        'phase matching lost ${(unmatchedFrameCount / observedFrameCount * 100).toStringAsFixed(1)}% of frames',
      );
    }
  }

  for (final key in const [
    'p95_build_ms',
    'p95_raster_ms',
    'p50_build_ms',
    'p50_raster_ms',
  ]) {
    final baselineValue = _readNumber(baseline, key);
    final candidateValue = _readNumber(candidate, key);
    if (baselineValue == null || baselineValue <= 0) {
      failures.add('baseline is missing a positive $key');
      continue;
    }
    if (candidateValue == null) {
      failures.add('candidate is missing $key');
      continue;
    }
    final ratio = candidateValue / baselineValue;
    if (ratio > _regressionThreshold) {
      failures.add(
        '$key regressed ${((ratio - 1) * 100).toStringAsFixed(1)}% '
        '($baselineValue -> $candidateValue)',
      );
    }
  }

  final unmatchedFrames = phaseMatch is Map<String, dynamic>
      ? phaseMatch['unmatched_frame_count']
      : 'unknown';
  stdout.writeln(
    'Measurement cycles: ${measurementCycles ?? 0}; '
    'interaction frames: ${sampleCount ?? 0}; '
    'unmatched: $unmatchedFrames; '
    'static background frames: ${staticBackgroundFrames ?? 'unknown'}',
  );
  stdout.writeln(
    'Interaction p50/p95/max ms: '
    'build ${_readNumber(candidate, 'p50_build_ms') ?? 0}/'
    '${_readNumber(candidate, 'p95_build_ms') ?? 0}/'
    '${_readNumber(candidate, 'max_build_ms') ?? 0}; '
    'raster ${_readNumber(candidate, 'p50_raster_ms') ?? 0}/'
    '${_readNumber(candidate, 'p95_raster_ms') ?? 0}/'
    '${_readNumber(candidate, 'max_raster_ms') ?? 0}; '
    'vsync overhead p95 ${_readNumber(candidate, 'p95_vsync_overhead_ms') ?? 0}; '
    'total span ${_readNumber(candidate, 'p95_total_span_ms') ?? 0}/'
    '${_readNumber(candidate, 'max_total_span_ms') ?? 0}',
  );
  stdout.writeln(
    'Interaction frames over 16.67 ms build/raster/total: '
    '${_readNumber(candidate, 'build_over_budget_frame_count') ?? 0}/'
    '${_readNumber(candidate, 'raster_over_budget_frame_count') ?? 0}/'
    '${_readNumber(candidate, 'total_over_budget_frame_count') ?? 0}',
  );
  if (failures.isNotEmpty) {
    stderr.writeln('Performance gate failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
  }
}

void _printActionResponseSummary(Map<String, dynamic> phases) {
  stdout.writeln(
    'Action response frame build max (limit < '
    '$_maximumActionResponseBuildMs ms):',
  );
  for (final phase in measuredInteractionPhases) {
    final metrics = phases[phase];
    if (metrics is! Map<String, dynamic>) {
      continue;
    }
    stdout.writeln(
      '  $phase: n=${_readNumber(metrics, 'sample_count') ?? 0}, '
      'max=${_readNumber(metrics, 'max_build_ms') ?? 0} ms',
    );
  }
}

void _printPhaseSummary(Map<String, dynamic> phases) {
  final entries = phases.entries.toList()
    ..sort((left, right) {
      final leftSpan = left.value is Map<String, dynamic>
          ? _readNumber(left.value, 'p95_total_span_ms') ?? 0
          : 0;
      final rightSpan = right.value is Map<String, dynamic>
          ? _readNumber(right.value, 'p95_total_span_ms') ?? 0
          : 0;
      return rightSpan.compareTo(leftSpan);
    });

  stdout.writeln('Frame phases by p95 total span:');
  for (final entry in entries) {
    final metrics = entry.value;
    if (metrics is! Map<String, dynamic>) {
      continue;
    }
    stdout.writeln(
      '  ${entry.key}: n=${_readNumber(metrics, 'sample_count') ?? 0}, '
      'build=${_readNumber(metrics, 'p95_build_ms') ?? 0} ms '
      '(max ${_readNumber(metrics, 'max_build_ms') ?? 0}), '
      'raster=${_readNumber(metrics, 'p95_raster_ms') ?? 0} ms '
      '(max ${_readNumber(metrics, 'max_raster_ms') ?? 0}), '
      'vsync=${_readNumber(metrics, 'p95_vsync_overhead_ms') ?? 0} ms, '
      'span=${_readNumber(metrics, 'p95_total_span_ms') ?? 0} ms, '
      'over-budget build/raster/total='
      '${_readNumber(metrics, 'build_over_budget_frame_count') ?? 0}/'
      '${_readNumber(metrics, 'raster_over_budget_frame_count') ?? 0}/'
      '${_readNumber(metrics, 'total_over_budget_frame_count') ?? 0}',
    );
  }
}

num? _readNumber(Map<String, dynamic> report, String key) {
  final value = report[key];
  if (value is! num || !value.isFinite || value < 0) {
    return null;
  }
  return value;
}

Map<String, String> _parseArguments(List<String> arguments) {
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (!argument.startsWith('--')) {
      throw ArgumentError('Unexpected argument: $argument');
    }
    final name = argument.substring(2);
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      throw ArgumentError('Missing value for --$name.');
    }
    if (options.containsKey(name)) {
      throw ArgumentError('Duplicate option --$name.');
    }
    options[name] = arguments[++index];
  }
  for (final required in const ['baseline', 'candidate']) {
    if (!options.containsKey(required)) {
      throw ArgumentError('Missing --$required.');
    }
  }
  final unexpected = options.keys
      .where((key) => key != 'baseline' && key != 'candidate')
      .toList();
  if (unexpected.isNotEmpty) {
    throw ArgumentError('Unexpected option --${unexpected.first}.');
  }
  return options;
}

Future<Map<String, dynamic>> _readReport(String path) async {
  final decoded = jsonDecode(await File(path).readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('$path must contain a JSON object.');
  }
  return decoded;
}
