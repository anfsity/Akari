import 'dart:io';

import 'model.dart';
import 'process.dart';
import 'report.dart';

Future<RunResult> runSteps(List<RunStep> steps, RunReport report) async {
  final startedAt = DateTime.now().toUtc();
  final stopwatch = Stopwatch()..start();
  final results = <String, Future<StepResult?>>{};
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
      await report.recordEvent('step_started', {
        'step_id': step.id,
        'command': report.redactor.redactCommand(step.command),
        'working_directory': step.workingDirectory,
        if (step.action != null) 'in_process': true,
      });
      if (report.format == RunOutputFormat.text) {
        stderr.writeln('==> ${index + 1}/${steps.length} ${step.id}');
      }
      final result = await runStep(
        step: step,
        repoRoot: report.repoRoot,
        runDirectoryPath: report.directoryPath,
        runDirectory: report.runDirectory,
        format: report.format,
        redactor: report.redactor,
      );
      await report.recordEvent('step_finished', {
        'step_id': step.id,
        'status': result.status,
        'exit_code': result.exitCode,
        'duration_ms': result.durationMs,
      });
      if (report.format == RunOutputFormat.text) {
        stderr.writeln(
          '<== ${step.id}: ${result.status} (${result.durationMs} ms)',
        );
      }
      return result;
    }();
  }
  final stepResults = (await Future.wait(results.values))
      .whereType<StepResult>()
      .toList();

  stopwatch.stop();
  final finishedAt = DateTime.now().toUtc();
  return RunResult(
    steps: stepResults,
    startedAt: startedAt,
    finishedAt: finishedAt,
    durationMs: stopwatch.elapsedMilliseconds,
  );
}
