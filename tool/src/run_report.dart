import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'theme_perf.dart';

enum RunOutputFormat { text, json }

void writeRunPlan({
  required String command,
  required String? reportPath,
  required Directory repoRoot,
  required String runDirectory,
  required List<RunStep> steps,
  required Map<String, String> artifactPaths,
  Map<String, Object?>? displayProfile,
}) {
  final runDirectoryPath = _join(repoRoot.path, runDirectory);
  final reportFile = reportPath == null
      ? File(_join(runDirectoryPath, 'report.json'))
      : File(_resolvePath(repoRoot, reportPath));
  final redactor = _SecretRedactor.fromEnvironments([
    Platform.environment,
    for (final step in steps) step.environment,
  ]);
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'schema_version': 1,
      'dry_run': true,
      'display': ?displayProfile,
      'run_id': _lastSegment(runDirectory),
      'command': command,
      'run_directory': _relativePath(repoRoot, runDirectoryPath),
      'report_path': _relativePath(repoRoot, reportFile.path),
      'artifacts': _resolveArtifactPaths(
        repoRoot,
        runDirectoryPath,
        artifactPaths,
      ),
      'steps': [
        for (final step in steps)
          {
            'id': step.id,
            'command': redactor.redactCommand(step.command),
            'working_directory': _resolvePath(repoRoot, step.workingDirectory),
            'environment': redactor.redactEnvironment(step.environment),
            'dependencies': step.dependencies,
            'interactive': step.interactive,
            if (step.action != null) 'in_process': true,
            'stdout_log': _join(runDirectory, '${step.id}.stdout.log'),
            'stderr_log': _join(runDirectory, '${step.id}.stderr.log'),
          },
      ],
    }),
  );
}

/// One process invocation or silent internal action. For an internal action,
/// command retains its standalone equivalent for plans and reports, avoiding
/// another Dart VM startup while sharing error handling and dependency ordering.
/// Dependencies refer to earlier step IDs:
/// null follows the preceding step, while an empty list starts independently.
/// Plans are ordered so every explicit prerequisite already exists in the runner.
class RunStep {
  const RunStep({
    required this.id,
    required this.command,
    required this.workingDirectory,
    required this.environment,
    this.dependencies,
    this.interactive = false,
    this.action,
  });

  final String id;
  final List<String> command;
  final String workingDirectory;
  final Map<String, String> environment;
  final List<String>? dependencies;
  final bool interactive;
  final FutureOr<void> Function()? action;
}

Future<int> runDevCommand({
  required String command,
  required RunOutputFormat format,
  required String? reportPath,
  required Directory repoRoot,
  required String runDirectory,
  required List<RunStep> steps,
  required Map<String, String> artifactPaths,
  Map<String, Object?>? displayProfile,
}) async {
  final runDirectoryPath = _join(repoRoot.path, runDirectory);
  await Directory(runDirectoryPath).create(recursive: true);
  final performanceOutput = artifactPaths['performance_output'];
  if (performanceOutput != null) {
    await Directory(_resolvePath(repoRoot, performanceOutput))
        .create(recursive: true);
  }
  final eventsPath = _join(runDirectoryPath, 'events.jsonl');
  final events = File(eventsPath).openWrite();
  final redactor = _SecretRedactor.fromEnvironments([
    Platform.environment,
    for (final step in steps) step.environment,
  ]);
  final startedAt = DateTime.now().toUtc();
  final stopwatch = Stopwatch()..start();
  final stepResults = <_StepResult>[];

  // Independent branches can finish concurrently. Chain event writes so one
  // event and its flush complete before the next appends to the shared log.
  var eventWrites = Future<void>.value();
  Future<void> recordEvent(String name, Map<String, Object?> fields) {
    eventWrites = eventWrites.then((_) async {
      events.writeln(
        jsonEncode({
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'run_id': _lastSegment(runDirectory),
          'event': name,
          ...fields,
        }),
      );
      await events.flush();
    });
    return eventWrites;
  }

  await recordEvent('run_started', {'command': command});
  if (format == RunOutputFormat.text) {
    stderr.writeln('Run ${_lastSegment(runDirectory)}: $command');
  }

  final results = <String, Future<_StepResult?>>{};
  // Construct futures in plan order, then wait for the whole graph. Awaiting
  // each step here would accidentally serialize independent build branches.
  for (var index = 0; index < steps.length; index++) {
    final step = steps[index];
    final dependencies =
        step.dependencies ?? (index == 0 ? <String>[] : [steps[index - 1].id]);
    final prerequisites = [for (final id in dependencies) results[id]!];
    results[step.id] = () async {
      final completed = await Future.wait(prerequisites);
      if (completed.any(
        (result) => result == null || result.status == 'failed',
      )) {
        return null;
      }
      await recordEvent('step_started', {
        'step_id': step.id,
        'command': redactor.redactCommand(step.command),
        'working_directory': step.workingDirectory,
        if (step.action != null) 'in_process': true,
      });
      if (format == RunOutputFormat.text) {
        stderr.writeln('==> ${index + 1}/${steps.length} ${step.id}');
      }
      final result = await _runStep(
        step: step,
        repoRoot: repoRoot,
        runDirectoryPath: runDirectoryPath,
        runDirectory: runDirectory,
        format: format,
        redactor: redactor,
      );
      await recordEvent('step_finished', {
        'step_id': step.id,
        'status': result.status,
        'exit_code': result.exitCode,
        'duration_ms': result.durationMs,
      });
      if (format == RunOutputFormat.text) {
        stderr.writeln(
          '<== ${step.id}: ${result.status} (${result.durationMs} ms)',
        );
      }
      return result;
    }();
  }
  stepResults.addAll(
    (await Future.wait(results.values)).whereType<_StepResult>(),
  );

  stopwatch.stop();
  final finishedAt = DateTime.now().toUtc();
  Map<String, String>? themeArtifacts;
  String? reportError;
  final performanceResultPath = artifactPaths['performance_result'];
  if (performanceResultPath != null) {
    final manifest = File(_resolvePath(repoRoot, performanceResultPath));
    final commandPassed = stepResults.every(
      (result) => result.status == 'passed',
    );
    // A failed theme may still publish diagnostic artifacts. A successful
    // theme must supply a valid manifest before the run can be reported passed.
    if (commandPassed || await manifest.exists()) {
      try {
        themeArtifacts = {
          for (final entry in (await getThemePerfArtifacts(manifest)).entries)
            entry.key: _relativePath(repoRoot, entry.value),
        };
      } catch (error) {
        reportError = redactor.redact('$error');
      }
    }
  }
  Map<String, Object?>? displayReport = displayProfile;
  final displayReportPath = artifactPaths['display_report'];
  if (displayReportPath != null) {
    final file = File(_resolvePath(repoRoot, displayReportPath));
    if (await file.exists()) {
      try {
        displayReport = (jsonDecode(await file.readAsString()) as Map)
            .cast<String, Object?>();
        if (displayReport['matched'] != true) {
          reportError = redactor.redact(
            '${displayReport['error'] ?? 'Sway outputs did not match the requested profile.'}',
          );
        }
      } catch (error) {
        reportError = redactor.redact(
          'Could not read Sway display report: $error',
        );
      }
    } else if (stepResults.every((result) => result.status == 'passed')) {
      reportError = 'Sway session did not publish its display report.';
    }
  }
  final status =
      stepResults.every((result) => result.status == 'passed') &&
          reportError == null
      ? 'passed'
      : 'failed';
  final reportErrorFields = reportError == null
      ? const <String, String>{}
      : {'error': reportError};
  final themeArtifactFields = themeArtifacts == null
      ? const <String, Object?>{}
      : {'theme_artifacts': themeArtifacts};
  final reportFile = reportPath == null
      ? File(_join(runDirectoryPath, 'report.json'))
      : File(_resolvePath(repoRoot, reportPath));
  await reportFile.parent.create(recursive: true);

  final resolvedArtifacts = _resolveArtifactPaths(
    repoRoot,
    runDirectoryPath,
    artifactPaths,
  );
  final report = <String, Object?>{
    'schema_version': 1,
    'run_id': _lastSegment(runDirectory),
    'display': ?displayReport,
    'command': command,
    'status': status,
    'started_at': startedAt.toIso8601String(),
    'finished_at': finishedAt.toIso8601String(),
    'duration_ms': stopwatch.elapsedMilliseconds,
    'artifacts': resolvedArtifacts,
    'steps': [for (final result in stepResults) result.toJson()],
    'report_path': _relativePath(repoRoot, reportFile.path),
    ...themeArtifactFields,
    ...reportErrorFields,
  };

  await recordEvent('run_finished', {
    'status': status,
    'duration_ms': stopwatch.elapsedMilliseconds,
    'report_path': _relativePath(repoRoot, reportFile.path),
    ...reportErrorFields,
  });
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  await events.close();

  if (format == RunOutputFormat.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } else {
    stderr.writeln(
      'Run $status. Report: ${_relativePath(repoRoot, reportFile.path)}',
    );
    stderr.writeln('Logs: ${_relativePath(repoRoot, runDirectoryPath)}');
    if (status == 'passed' && resolvedArtifacts.containsKey('bundle_link')) {
      stderr.writeln('Frontend: ${resolvedArtifacts['bundle_link']}/greeter');
      stderr.writeln('Backend: ${resolvedArtifacts['backend_link']}');
    }
  }
  if (status == 'passed') return 0;
  if (performanceResultPath != null) {
    for (final result in stepResults) {
      if (result.status == 'failed') return result.exitCode ?? 1;
    }
  }
  return 1;
}

Future<_StepResult> _runStep({
  required RunStep step,
  required Directory repoRoot,
  required String runDirectoryPath,
  required String runDirectory,
  required RunOutputFormat format,
  required _SecretRedactor redactor,
}) async {
  final startedAt = DateTime.now().toUtc();
  final stopwatch = Stopwatch()..start();
  final logName = step.id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  final stdoutPath = _join(runDirectoryPath, '$logName.stdout.log');
  final stderrPath = _join(runDirectoryPath, '$logName.stderr.log');
  final stdoutLog = File(stdoutPath).openWrite();
  final stderrLog = File(stderrPath).openWrite();
  int? processExitCode;
  Object? failure;
  StreamSubscription<List<int>>? input;
  final signals = <StreamSubscription<ProcessSignal>>[];
  final terminal = step.interactive && stdin.hasTerminal;
  final originalLineMode = terminal ? stdin.lineMode : null;
  final originalEchoMode = terminal ? stdin.echoMode : null;

  try {
    if (step.action case final action?) {
      await action();
      processExitCode = 0;
    } else {
      // A separate process group lets forwarded signals reach shell wrappers and
      // their descendants, including Flutter/backend processes, not just setsid.
      final process = await Process.start(
        'setsid',
        step.command,
        workingDirectory: _resolvePath(repoRoot, step.workingDirectory),
        environment: step.environment.isEmpty
            ? null
            : {...Platform.environment, ...step.environment},
      );
      for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
        signals.add(
          signal.watch().listen((_) {
            Process.killPid(-process.pid, signal);
          }),
        );
      }
      if (step.interactive) {
        if (terminal) {
          stdin.lineMode = false;
          stdin.echoMode = false;
        }
        input = stdin.listen(process.stdin.add, onDone: process.stdin.close);
      }
      final stdoutCopy = _copyOutput(
        process.stdout,
        stdoutLog,
        format == RunOutputFormat.text ? stdout : null,
        redactor,
      );
      final stderrCopy = _copyOutput(
        process.stderr,
        stderrLog,
        format == RunOutputFormat.text ? stderr : null,
        redactor,
      );
      processExitCode = await process.exitCode;
      await Future.wait([stdoutCopy, stderrCopy]);
    }
  } catch (error) {
    failure = error;
    stderrLog.writeln('Could not complete step: ${redactor.redact('$error')}');
    if (format == RunOutputFormat.text) {
      stderr.writeln(
        'Could not complete step ${step.id}: ${redactor.redact('$error')}',
      );
    }
  } finally {
    // Cancelling Dart's stdin subscription can close the terminal descriptor.
    // Restore its flags while the descriptor is still owned by this step.
    if (terminal) {
      stdin.lineMode = originalLineMode!;
      stdin.echoMode = originalEchoMode!;
    }
    await input?.cancel();
    for (final signal in signals) {
      await signal.cancel();
    }
    await Future.wait([stdoutLog.flush(), stderrLog.flush()]);
    await Future.wait([stdoutLog.close(), stderrLog.close()]);
  }

  stopwatch.stop();
  final finishedAt = DateTime.now().toUtc();
  final succeeded = failure == null && processExitCode == 0;
  return _StepResult(
    id: step.id,
    command: redactor.redactCommand(step.command),
    workingDirectory: step.workingDirectory,
    status: succeeded ? 'passed' : 'failed',
    exitCode: processExitCode,
    startedAt: startedAt,
    finishedAt: finishedAt,
    durationMs: stopwatch.elapsedMilliseconds,
    stdoutLog: _join(runDirectory, '$logName.stdout.log'),
    stderrLog: _join(runDirectory, '$logName.stderr.log'),
    error: failure == null ? null : redactor.redact('$failure'),
    inProcess: step.action != null,
  );
}

Future<void> _copyOutput(
  Stream<List<int>> input,
  IOSink log,
  IOSink? mirror,
  _SecretRedactor redactor,
) async {
  // Redact whole lines: a pipe chunk can split a secret across boundaries.
  // Chunk-local replacement would leak fragments into both logs and mirrors.
  var pending = '';
  await for (final chunk in input.transform(utf8.decoder)) {
    pending += chunk;
    var lineEnd = pending.indexOf('\n');
    while (lineEnd >= 0) {
      final line = redactor.redact(pending.substring(0, lineEnd + 1));
      log.write(line);
      mirror?.write(line);
      pending = pending.substring(lineEnd + 1);
      lineEnd = pending.indexOf('\n');
    }
  }
  if (pending.isNotEmpty) {
    final remainder = redactor.redact(pending);
    log.write(remainder);
    mirror?.write(remainder);
  }
  await log.flush();
}

String _resolvePath(Directory repoRoot, String path) {
  return File(path).isAbsolute ? path : _join(repoRoot.path, path);
}

String _relativePath(Directory repoRoot, String path) {
  final absolutePath = File(path).absolute.path;
  final rootPath = repoRoot.absolute.path;
  if (absolutePath == rootPath) {
    return '.';
  }
  if (absolutePath.startsWith('$rootPath${Platform.pathSeparator}')) {
    return absolutePath.substring(rootPath.length + 1);
  }
  return absolutePath;
}

String _join(String base, String relative) {
  return '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
}

Map<String, String> _resolveArtifactPaths(
  Directory repoRoot,
  String runDirectoryPath,
  Map<String, String> artifactPaths,
) {
  return {
    'run_directory': _relativePath(repoRoot, runDirectoryPath),
    'events': _relativePath(repoRoot, _join(runDirectoryPath, 'events.jsonl')),
    for (final entry in artifactPaths.entries)
      entry.key: _relativePath(repoRoot, _join(repoRoot.path, entry.value)),
  };
}

String _lastSegment(String path) => path.split(Platform.pathSeparator).last;

/// Masks known sensitive environment values and common credential syntax in
/// plans, reports, and captured output. This is a logging safeguard, not a
/// reason for child commands to print arbitrary credentials or PAM payloads.
class _SecretRedactor {
  _SecretRedactor(this._secretValues);

  static final _sensitiveEnvironmentName = RegExp(
    r'(?:^|[_-])(?:password|passwd|passphrase|token|secret|api[_-]?key|credential|authorization)(?:$|[_-])|pam.*(?:response|answer)',
    caseSensitive: false,
  );
  static final _sensitiveAssignment = RegExp(
    r"""([\"']?(?:password|passwd|passphrase|token|access[_-]?token|refresh[_-]?token|api[_-]?key|credential|authorization|pam[_-]?(?:secret|password|response))[\"']?\s*[:=]\s*)(?:\"[^\"]*\"|'[^']*'|[^\s,;]+)""",
    caseSensitive: false,
  );
  static final _sensitiveOptionValue = RegExp(
    r'''(--(?:password|passwd|passphrase|token|access[_-]?token|refresh[_-]?token|api[_-]?key|credential|authorization|pam[_-]?(?:secret|password|response))\s+)(?:"[^"]*"|'[^']*'|[^\s,;]+)''',
    caseSensitive: false,
  );
  static final _sensitiveOption = RegExp(
    r'^--(?:password|passwd|passphrase|token|access[_-]?token|refresh[_-]?token|api[_-]?key|credential|authorization|pam[_-]?(?:secret|password|response))$',
    caseSensitive: false,
  );
  static final _bearerToken = RegExp(
    r'\bBearer\s+[^\s,;]+',
    caseSensitive: false,
  );

  final List<String> _secretValues;

  factory _SecretRedactor.fromEnvironments(
    Iterable<Map<String, String>> environments,
  ) {
    final secretValues = <String>{};
    for (final environment in environments) {
      for (final entry in environment.entries) {
        if (_sensitiveEnvironmentName.hasMatch(entry.key) &&
            entry.value.isNotEmpty) {
          secretValues.add(entry.value);
        }
      }
    }
    // Replace longer values first so a shorter overlapping secret does not
    // destroy the match and leave the remaining suffix of a longer one exposed.
    final sortedSecrets = secretValues.toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    return _SecretRedactor(sortedSecrets);
  }

  List<String> redactCommand(List<String> command) {
    final safeCommand = <String>[];
    for (var index = 0; index < command.length; index++) {
      final argument = command[index];
      safeCommand.add(redact(argument));
      if (_sensitiveOption.hasMatch(argument) && index + 1 < command.length) {
        safeCommand.add('[REDACTED]');
        index++;
      }
    }
    return safeCommand;
  }

  Map<String, String> redactEnvironment(Map<String, String> environment) => {
    for (final entry in environment.entries)
      entry.key: _sensitiveEnvironmentName.hasMatch(entry.key)
          ? '[REDACTED]'
          : redact(entry.value),
  };

  String redact(String value) {
    var sanitized = value;
    for (final secret in _secretValues) {
      sanitized = sanitized.replaceAll(secret, '[REDACTED]');
    }
    sanitized = sanitized.replaceAllMapped(_sensitiveAssignment, (match) {
      final assignedValue = match.group(0)!.substring(match.group(1)!.length);
      final quote = assignedValue.startsWith('"')
          ? '"'
          : assignedValue.startsWith("'")
          ? "'"
          : '';
      return '${match.group(1)}$quote[REDACTED]$quote';
    });
    sanitized = sanitized.replaceAllMapped(
      _sensitiveOptionValue,
      (match) => '${match.group(1)}[REDACTED]',
    );
    return sanitized.replaceAll(_bearerToken, 'Bearer [REDACTED]');
  }
}

class _StepResult {
  const _StepResult({
    required this.id,
    required this.command,
    required this.workingDirectory,
    required this.status,
    required this.exitCode,
    required this.startedAt,
    required this.finishedAt,
    required this.durationMs,
    required this.stdoutLog,
    required this.stderrLog,
    required this.error,
    required this.inProcess,
  });

  final String id;
  final List<String> command;
  final String workingDirectory;
  final String status;
  final int? exitCode;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int durationMs;
  final String stdoutLog;
  final String stderrLog;
  final String? error;
  final bool inProcess;

  Map<String, Object?> toJson() => {
    'id': id,
    'command': command,
    if (inProcess) 'in_process': true,
    'working_directory': workingDirectory,
    'status': status,
    'exit_code': exitCode,
    'started_at': startedAt.toIso8601String(),
    'finished_at': finishedAt.toIso8601String(),
    'duration_ms': durationMs,
    'stdout_log': stdoutLog,
    'stderr_log': stderrLog,
    if (error != null) 'error': error,
  };
}
