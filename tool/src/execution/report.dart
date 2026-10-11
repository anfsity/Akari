import 'dart:convert';
import 'dart:io';

import 'model.dart';
import 'paths.dart';
import 'redaction.dart';

/// Owns the event stream and presentation for one run. Command-specific result
/// validation is supplied as completion data, never inferred from artifact keys.
class RunReport {
  RunReport({
    required this.command,
    required this.format,
    required this.repoRoot,
    required this.runDirectory,
    required this.steps,
    required this.artifactPaths,
    this.reportPath,
    this.displayProfile,
  }) : redactor = SecretRedactor.fromEnvironments([
         Platform.environment,
         for (final step in steps) step.environment,
       ]);

  final String command;
  final RunOutputFormat format;
  final Directory repoRoot;
  final String runDirectory;
  final List<RunStep> steps;
  final Map<String, String> artifactPaths;
  final String? reportPath;
  final Map<String, Object?>? displayProfile;
  final SecretRedactor redactor;
  late final IOSink _events;
  Future<void> _eventWrites = Future<void>.value();

  String get directoryPath => getAbsolutePath(repoRoot, runDirectory);
  String get _runId => runDirectory.split(Platform.pathSeparator).last;
  File get _reportFile => File(
    getAbsolutePath(
      repoRoot,
      reportPath ?? getJoinedPath(runDirectory, 'report.json'),
    ),
  );

  Map<String, String> getArtifacts() => {
    'run_directory': getRelativePath(repoRoot, directoryPath),
    'events': getRelativePath(
      repoRoot,
      getJoinedPath(directoryPath, 'events.jsonl'),
    ),
    for (final entry in artifactPaths.entries)
      entry.key: getRelativePath(
        repoRoot,
        getAbsolutePath(repoRoot, entry.value),
      ),
  };

  Map<String, Object?> _getIdentity() => {
    'schema_version': 1,
    'run_id': _runId,
    'command': command,
    'display': ?displayProfile,
    'artifacts': getArtifacts(),
    'report_path': getRelativePath(repoRoot, _reportFile.path),
  };

  void writePlan() {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        ..._getIdentity(),
        'dry_run': true,
        'run_directory': getRelativePath(repoRoot, directoryPath),
        'steps': [
          for (final step in steps)
            {
              'id': step.id,
              'command': redactor.redactCommand(step.command),
              'working_directory': getAbsolutePath(
                repoRoot,
                step.workingDirectory,
              ),
              'environment': redactor.redactEnvironment(step.environment),
              'dependencies': step.dependencies,
              'interactive': step.interactive,
              if (step.action != null) 'in_process': true,
              'stdout_log': getJoinedPath(
                runDirectory,
                '${step.id}.stdout.log',
              ),
              'stderr_log': getJoinedPath(
                runDirectory,
                '${step.id}.stderr.log',
              ),
            },
        ],
      }),
    );
  }

  Future<void> start() async {
    await Directory(directoryPath).create(recursive: true);
    _events = File(getJoinedPath(directoryPath, 'events.jsonl')).openWrite();
    await recordEvent('run_started', {'command': command});
    if (format == RunOutputFormat.text) {
      stderr.writeln('Run $_runId: $command');
    }
  }

  Future<void> recordEvent(String name, Map<String, Object?> fields) {
    // Parallel steps share one stream. Serialize each append and flush so
    // independent completions cannot interleave JSON records.
    _eventWrites = _eventWrites.then((_) async {
      _events.writeln(
        jsonEncode({
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'run_id': _runId,
          'event': name,
          ...fields,
        }),
      );
      await _events.flush();
    });
    return _eventWrites;
  }

  Future<int> finish(RunResult result, RunCompletion completion) async {
    final passed = result.isPassed && completion.error == null;
    final status = passed ? 'passed' : 'failed';
    final error = completion.error;
    final errorFields = {if (error != null) 'error': redactor.redact(error)};
    final report = {
      ..._getIdentity(),
      'status': status,
      'started_at': result.startedAt.toIso8601String(),
      'finished_at': result.finishedAt.toIso8601String(),
      'duration_ms': result.durationMs,
      'steps': [for (final step in result.steps) step.toJson()],
      ...completion.fields,
      ...errorFields,
    };
    await _reportFile.parent.create(recursive: true);
    await recordEvent('run_finished', {
      'status': status,
      'duration_ms': result.durationMs,
      'report_path': getRelativePath(repoRoot, _reportFile.path),
      ...errorFields,
    });
    final encoded = const JsonEncoder.withIndent('  ').convert(report);
    await _reportFile.writeAsString(encoded);
    if (format == RunOutputFormat.json) {
      stdout.writeln(encoded);
    } else {
      stderr.writeln(
        'Run $status. Report: ${getRelativePath(repoRoot, _reportFile.path)}',
      );
      stderr.writeln('Logs: ${getRelativePath(repoRoot, directoryPath)}');
      final artifacts = getArtifacts();
      if (passed && artifacts.containsKey('bundle_link')) {
        stderr.writeln('Frontend: ${artifacts['bundle_link']}/greeter');
        stderr.writeln('Backend: ${artifacts['backend_link']}');
      }
    }
    return passed ? 0 : completion.failureExitCode;
  }

  Future<void> close() async {
    await _eventWrites;
    await _events.close();
  }
}
