import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:akari_cli/src/commands/development.dart';
import 'package:akari_cli/src/commands/plan.dart';
import 'package:akari_cli/src/execution/model.dart';
import 'package:akari_cli/src/theme/display_profile.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('akari-plan-');
  });
  tearDown(() => root.delete(recursive: true));

  for (final cached in [false, true]) {
    test('artifact paths preserve files and links (cached: $cached)', () async {
      final executable = File('${root.path}/build/backend');
      final link = Link('${root.path}/build/out/backend');
      if (cached) {
        await executable.parent.create(recursive: true);
        await executable.writeAsString('cached');
        await link.parent.create(recursive: true);
        await link.create('../backend');
      }

      final code = await runPlan(
        RunPlan(
          command: 'build',
          artifactPaths: const {
            'backend_executable': 'build/backend',
            'backend_link': 'build/out/backend',
          },
          steps: [
            RunStep(
              id: 'build.backend',
              command: const ['build-backend'],
              action: () async {
                expect(await executable.exists(), cached);
                expect(await link.exists(), cached);
                await executable.parent.create(recursive: true);
                await executable.writeAsString('built');
                if (!cached) {
                  await link.parent.create(recursive: true);
                  await link.create('../backend');
                }
              },
            ),
          ],
        ),
        repoRoot: root,
        runDirectory: 'run',
        format: RunOutputFormat.json,
      );

      expect(code, 0);
      expect(await executable.readAsString(), 'built');
      expect(await File(link.path).readAsString(), 'built');
      expect(await link.target(), '../backend');
    });
  }

  test(
    'artifact labels do not impose another command success contract',
    () async {
      final code = await runPlan(
        const RunPlan(
          command: 'custom',
          steps: [],
          artifactPaths: {
            'performance_result': 'absent.json',
            'display_report': 'also-absent.json',
          },
        ),
        repoRoot: root,
        runDirectory: 'run',
        format: RunOutputFormat.json,
      );
      expect(code, 0);
      final report = jsonDecode(
        await File('${root.path}/run/report.json').readAsString(),
      );
      expect(report['status'], 'passed');
      expect(report['artifacts']['performance_result'], 'absent.json');
    },
  );

  test(
    'command validation finishes before final report and completion event',
    () async {
      final directory = '${root.path}/run';
      final code = await runPlan(
        RunPlan(
          command: 'custom',
          steps: const [
            RunStep(id: 'check', command: ['true']),
          ],
          getCompletion: (result) async {
            expect(result.isPassed, true);
            expect(await File('$directory/report.json').exists(), false);
            final events = await File('$directory/events.jsonl').readAsLines();
            expect(events.map((line) => jsonDecode(line)['event']), [
              'run_started',
              'step_started',
              'step_finished',
            ]);
            return const RunCompletion(
              error: 'result rejected',
              failureExitCode: 17,
              fields: {'diagnostic': 'retained'},
            );
          },
        ),
        repoRoot: root,
        runDirectory: 'run',
        format: RunOutputFormat.json,
      );
      expect(code, 17);
      final report = jsonDecode(
        await File('$directory/report.json').readAsString(),
      );
      expect(report['status'], 'failed');
      expect(report['error'], 'result rejected');
      expect(report['diagnostic'], 'retained');
      final event = jsonDecode(
        (await File('$directory/events.jsonl').readAsLines()).last,
      );
      expect(event['event'], 'run_finished');
      expect(event['status'], 'failed');
    },
  );

  test(
    'failed branch aborts pending sibling branches and display completion preserves exit code',
    () async {
      final ranSibling = File('${root.path}/sibling-ran');
      final blocker = Completer<void>();
      final code = await runPlan(
        RunPlan(
          command: 'custom',
          steps: [
            RunStep(
              id: 'failing.root',
              command: const ['false'],
              dependencies: const [],
              action: () {
                blocker.complete();
                throw StateError('boom');
              },
            ),
            RunStep(
              id: 'sibling.gate',
              command: const ['true'],
              dependencies: const [],
              action: () => blocker.future,
            ),
            RunStep(
              id: 'sibling.child',
              command: const ['true'],
              dependencies: const ['sibling.gate'],
              action: () => ranSibling.writeAsString('ran'),
            ),
          ],
          getCompletion: (result) => getDisplayCompletion(
            File('${root.path}/missing-display.json'),
            result,
          ),
        ),
        repoRoot: root,
        runDirectory: 'abort',
        format: RunOutputFormat.json,
      );
      expect(code, 1);
      expect(ranSibling.existsSync(), isFalse);
      final completion = await getDisplayCompletion(
        File('${root.path}/missing-display.json'),
        RunResult(
          steps: [
            StepResult(
              id: 'theme.sway',
              command: const ['sway'],
              workingDirectory: '.',
              status: 'failed',
              exitCode: 42,
              startedAt: DateTime.now(),
              finishedAt: DateTime.now(),
              durationMs: 1,
              stdoutLog: '',
              stderrLog: '',
              error: 'failed',
              inProcess: false,
            ),
          ],
          startedAt: DateTime.now(),
          finishedAt: DateTime.now(),
          durationMs: 1,
        ),
      );
      expect(completion.failureExitCode, 42);
    },
  );
}
