import 'dart:async';

enum RunOutputFormat { text, json }

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
    this.workingDirectory = '.',
    this.environment = const {},
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

class RunResult {
  const RunResult({
    required this.steps,
    required this.startedAt,
    required this.finishedAt,
    required this.durationMs,
  });

  final List<StepResult> steps;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int durationMs;

  bool get isPassed => steps.every((step) => step.status == 'passed');

  int getFirstFailureExitCode() {
    for (final step in steps) {
      if (step.status == 'failed') return step.exitCode ?? 1;
    }
    return 1;
  }
}

/// Command-owned validation adds report fields and decides its failure code.
/// The executor only knows whether individual steps completed successfully.
class RunCompletion {
  const RunCompletion({
    this.fields = const {},
    this.error,
    this.failureExitCode = 1,
  });

  final Map<String, Object?> fields;
  final String? error;
  final int failureExitCode;
}

class StepResult {
  const StepResult({
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
