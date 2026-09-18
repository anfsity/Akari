import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  final baseline = await _readReport(options['baseline']!);
  final candidate = await _readReport(options['candidate']!);

  final failures = <String>[];
  final staticBackgroundFrames =
      candidate['static_background_scheduled_frames'] as num?;
  if (staticBackgroundFrames != null && staticBackgroundFrames > 1) {
    failures.add('static background scheduled continuous frames after settle');
  }

  for (final key in const [
    'p95_build_ms',
    'p95_raster_ms',
    'p50_build_ms',
    'p50_raster_ms',
  ]) {
    final baselineValue = baseline[key] as num?;
    final candidateValue = candidate[key] as num?;
    if (baselineValue == null || candidateValue == null || baselineValue <= 0) {
      continue;
    }
    final ratio = candidateValue / baselineValue;
    if (ratio > 1.20) {
      failures.add(
        '$key regressed ${((ratio - 1) * 100).toStringAsFixed(1)}% '
        '($baselineValue -> $candidateValue)',
      );
    }
  }

  stdout.writeln('candidate: $candidate');
  if (failures.isNotEmpty) {
    stderr.writeln('Performance gate failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
  }
}

Map<String, String> _parseArguments(List<String> arguments) {
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument.startsWith('--')) {
      options[argument.substring(2)] = arguments[++index];
    }
  }
  for (final required in const ['baseline', 'candidate']) {
    if (!options.containsKey(required)) {
      throw ArgumentError('Missing --$required.');
    }
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
