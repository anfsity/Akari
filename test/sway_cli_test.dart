import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/run_report.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mozais-sway-cli-');
  });
  tearDown(() => temp.delete(recursive: true));

  Future<ProcessResult> runTool(List<String> arguments) => Process.run(
    '${Directory.current.path}/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart',
    ['tool/mozais.dart', ...arguments],
    environment: {'XDG_STATE_HOME': temp.path},
  );

  test('Sway plan reuses selected theme, mock backend and private bus without writes', () async {
    final result = await runTool([
      'run',
      'sway',
      '--theme',
      'themes/fallback',
      '--display-profile',
      'reference',
      '--resolution',
      '2560x1440',
      '--scale',
      '2',
      '--jobs',
      '3',
      '--dry-run',
    ]);
    expect(result.exitCode, 0, reason: result.stderr);
    final plan = jsonDecode(result.stdout as String) as Map;
    expect(plan['display']['custom'], true);
    expect(plan['display']['source']['kind'], 'reference');
    expect(plan['display']['outputs'].single['rect']['width'], 1280);
    final steps = (plan['steps'] as List).cast<Map>();
    expect(
      steps.first['command'],
      containsAllInOrder(['--features', 'mock', '--jobs', '3']),
    );
    expect(steps.last['id'], 'theme.sway');
    final command = steps.last['command'] as List;
    expect(command, contains(endsWith('scripts/debug-dbus.sh')));
    expect(command, contains(endsWith('scripts/sway-session.py')));
    expect(command, contains(endsWith('themes/fallback')));
    expect(command, isNot(contains(contains('tool/dev_main.dart'))));
    expect(steps.last['environment']['MOZAIS_BACKEND_MODE'], 'mock');
    expect(steps.last['dependencies'], ['backend.build', 'theme.host.pub_get']);
    expect(
      plan['artifacts']['display_report'],
      endsWith('/sway/display-report.json'),
    );
    expect(plan['artifacts']['screenshots'], endsWith('/sway/screenshots'));
    expect(Directory(plan['run_directory'] as String).existsSync(), false);
    expect(temp.listSync(), isEmpty);
  });

  test(
    'explicit production transport and headless backend reach the session',
    () async {
      final result = await runTool([
        'run',
        'sway',
        '--display-profile=reference',
        '--backend=real',
        '--sway-backend=headless',
        '--mode=release',
        '--dry-run',
      ]);
      expect(result.exitCode, 0, reason: result.stderr);
      final plan = jsonDecode(result.stdout as String) as Map;
      final steps = plan['steps'] as List;
      expect(steps.first['command'], contains('--release'));
      expect(steps.first['command'], isNot(contains('--features')));
      expect(
        steps.last['command'],
        containsAllInOrder(['--backend', 'headless', '--']),
      );
      expect(
        plan['artifacts']['backend_executable'],
        contains('mozais-real/release'),
      );
    },
  );

  test('help and parsing scope display options to Sway', () async {
    final help = await runTool(['run', 'sway', '--help']);
    expect(help.exitCode, 0);
    for (final option in [
      '--display-profile',
      '--resolution',
      '--scale',
      '--sway-backend',
    ]) {
      expect(help.stdout, contains(option));
    }
    for (final arguments in [
      ['run', '--scale=2', '--dry-run'],
      ['run', 'studio', '--display-profile=reference', '--dry-run'],
      ['run', 'sway', '--display-profile=unknown', '--dry-run'],
      ['run', 'sway', '--display-profile=reference', '--scale=0', '--dry-run'],
      [
        'run',
        'sway',
        '--display-profile=reference',
        '--scale=nan',
        '--dry-run',
      ],
      [
        'run',
        'sway',
        '--display-profile=reference',
        '--resolution=0x10',
        '--dry-run',
      ],
      [
        'run',
        'sway',
        '--display-profile=reference',
        '--resolution=1920',
        '--dry-run',
      ],
      ['run', 'sway', '--sway-backend=drm', '--dry-run'],
    ]) {
      final result = await runTool(arguments);
      expect(result.exitCode, 2, reason: '$arguments: ${result.stderr}');
    }
    expect(temp.listSync(), isEmpty);
  });

  test(
    'run reports include adopted outputs and fail a silent display mismatch',
    () async {
      for (final matched in [true, false]) {
        final run = matched ? 'matched' : 'mismatch';
        final displayFile = File('${temp.path}/$run/display-report.json');
        final status = await runDevCommand(
          command: 'run sway',
          format: RunOutputFormat.text,
          reportPath: null,
          repoRoot: temp,
          runDirectory: run,
          displayProfile: {
            'source': {'kind': 'reference'},
          },
          artifactPaths: {'display_report': '$run/display-report.json'},
          steps: [
            RunStep(
              id: 'theme.sway',
              command: const ['session'],
              workingDirectory: '.',
              environment: const {},
              action: () async {
                await displayFile.writeAsString(
                  jsonEncode({
                    'matched': matched,
                    'target': [1920, 1080],
                    'actual': [1280, 720],
                  }),
                );
              },
            ),
          ],
        );
        expect(status, matched ? 0 : 1);
        final report = jsonDecode(
          await File('${temp.path}/$run/report.json').readAsString(),
        );
        expect(report['display']['matched'], matched);
        expect(report['status'], matched ? 'passed' : 'failed');
      }
    },
  );

  test('successful session cannot omit the required display report', () async {
    final status = await runDevCommand(
      command: 'run sway',
      format: RunOutputFormat.text,
      reportPath: null,
      repoRoot: temp,
      runDirectory: 'missing',
      artifactPaths: {'display_report': 'missing/display-report.json'},
      steps: const [],
    );
    expect(status, 1);
    final report = jsonDecode(
      await File('${temp.path}/missing/report.json').readAsString(),
    );
    expect(report['error'], contains('did not publish'));
  });

}
