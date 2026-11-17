import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'model.dart';
import 'process.dart';
import 'report.dart';

Future<RunResult> runSteps(
  List<RunStep> steps,
  RunReport report, {
  int? maxConcurrency,
}) async {
  final startedAt = DateTime.now().toUtc();
  final stopwatch = Stopwatch()..start();
  final stepIds = {for (final step in steps) step.id};
  final results = <String, Future<StepResult?>>{};
  final abortCompleter = Completer<void>();
  final limiter = _ConcurrencyLimiter(
    maxConcurrency ?? Platform.numberOfProcessors.clamp(2, 8),
  );
  var aborted = false;

  void abortRun() {
    if (!aborted) {
      aborted = true;
      if (!abortCompleter.isCompleted) {
        abortCompleter.complete();
      }
    }
  }

  // Construct futures in plan order, then wait for the whole graph. Awaiting
  // each step here would accidentally serialize independent build branches.
  for (var index = 0; index < steps.length; index++) {
    final step = steps[index];
    final dependencies =
        step.dependencies ?? (index == 0 ? <String>[] : [steps[index - 1].id]);
    for (final id in dependencies) {
      if (!stepIds.contains(id) || !results.containsKey(id)) {
        throw StateError(
          'Step "${step.id}" depends on unknown or later step "$id".',
        );
      }
    }
    final prerequisites = [for (final id in dependencies) results[id]!];
    results[step.id] = () async {
      final completed = await Future.wait(prerequisites);
      if (aborted ||
          completed.any(
            (result) => result == null || result.status == 'failed',
          )) {
        return null;
      }
      final needsSlot = step.action == null && !step.interactive;
      if (needsSlot) {
        await limiter.lock();
      }
      try {
        if (aborted) {
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
          abortSignal: abortCompleter.future,
        );
        if (result.status == 'failed') {
          abortRun();
        }
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
      } finally {
        if (needsSlot) {
          limiter.unlock();
        }
      }
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

class _ConcurrencyLimiter {
  _ConcurrencyLimiter(this.limit) : assert(limit > 0);

  final int limit;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> lock() {
    if (_active < limit) {
      _active++;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.addLast(waiter);
    return waiter.future;
  }

  void unlock() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    _active--;
  }
}
