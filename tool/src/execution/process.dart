import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'model.dart';
import 'paths.dart';
import 'redaction.dart';

Future<StepResult> runStep({
  required RunStep step,
  required Directory repoRoot,
  required String runDirectoryPath,
  required String runDirectory,
  required RunOutputFormat format,
  required SecretRedactor redactor,
}) async {
  final startedAt = DateTime.now().toUtc();
  final stopwatch = Stopwatch()..start();
  final logName = step.id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  final stdoutPath = getJoinedPath(runDirectoryPath, '$logName.stdout.log');
  final stderrPath = getJoinedPath(runDirectoryPath, '$logName.stderr.log');
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
        workingDirectory: getAbsolutePath(repoRoot, step.workingDirectory),
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
  return StepResult(
    id: step.id,
    command: redactor.redactCommand(step.command),
    workingDirectory: step.workingDirectory,
    status: succeeded ? 'passed' : 'failed',
    exitCode: processExitCode,
    startedAt: startedAt,
    finishedAt: finishedAt,
    durationMs: stopwatch.elapsedMilliseconds,
    stdoutLog: getJoinedPath(runDirectory, '$logName.stdout.log'),
    stderrLog: getJoinedPath(runDirectory, '$logName.stderr.log'),
    error: failure == null ? null : redactor.redact('$failure'),
    inProcess: step.action != null,
  );
}

Future<void> _copyOutput(
  Stream<List<int>> input,
  IOSink log,
  IOSink? mirror,
  SecretRedactor redactor,
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
