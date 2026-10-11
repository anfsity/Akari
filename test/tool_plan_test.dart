import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/commands/development.dart';
import '../tool/src/commands/plan.dart';
import '../tool/src/execution/model.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('akari-plan-');
  });
  tearDown(() => root.delete(recursive: true));

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
          collectResult: (result) async {
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
}
