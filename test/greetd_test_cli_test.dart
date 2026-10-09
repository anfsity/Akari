import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/greetd_test.dart';
import '../tool/src/sdk_commands.dart';

void main() {
  late Directory temporary;
  late Directory installation;
  late Directory bin;
  late File runner;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('akari-greetd-cli-');
    installation = Directory('${temporary.path}/installation with spaces');
    bin = Directory('${temporary.path}/bin');
    await installation.create();
    await bin.create();
    for (final name in ['start.sh', 'restore.sh']) {
      await File('${installation.path}/$name')
          .writeAsString('unused test script');
    }
    final boundary = File('${bin.path}/boundary');
    await boundary.writeAsString('''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
if name == 'id':
    print(os.environ.get('FAKE_UID', '1000'))
elif name == 'sudo':
    pathlib.Path(os.environ['CALLS']).write_text(json.dumps(sys.argv[1:]))
    sys.exit(17)
elif name == 'systemctl':
    if os.environ.get('FAIL_SYSTEMD'):
        print('Failed to connect to systemd', file=sys.stderr)
        sys.exit(1)
    print('Id=sddm.service\\nLoadState=loaded\\nActiveState=active\\nSubState=running\\n')
    print('Id=akari-test.service\\nLoadState=not-found\\nActiveState=inactive\\nSubState=dead\\n')
    print('Id=akari-restore.timer\\nLoadState=not-found\\nActiveState=inactive\\nSubState=dead')
    sys.exit(1)
''');
    expect((await Process.run('chmod', ['+x', boundary.path])).exitCode, 0);
    for (final name in ['id', 'sudo', 'systemctl']) {
      await Link('${bin.path}/$name').create(boundary.path);
    }
    runner = File('${temporary.path}/runner.dart');
    await runner.writeAsString('''
import 'dart:io';
import '${Directory.current.uri}tool/src/greetd_test.dart';
import '${Directory.current.uri}tool/src/cli_definition.dart';
Future<void> main(List<String> arguments) async {
  try {
    exitCode = await runGreetdTestCommand(
      getCliCommand('greetd-test ' + arguments.first),
      arguments.skip(1).toList(),
      installation: Directory(Platform.environment['INSTALLATION']!),
      repoRoot: Directory(Platform.environment['REPOSITORY']!),
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
''');
  });
  tearDown(() => temporary.delete(recursive: true));

  Future<ProcessResult> runFixture(
    List<String> arguments, {
    Map<String, String> environment = const {},
  }) {
    final dart = getDartCommand(Directory.current);
    return Process.run(
      dart.first,
      [...dart.skip(1), runner.path, ...arguments],
      workingDirectory: temporary.path,
      environment: {
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
        'INSTALLATION': installation.path,
        'REPOSITORY': Directory.current.path,
        'CALLS': '${temporary.path}/calls.json',
        ...environment,
      },
    );
  }

  Future<Directory> createRun(String name) async {
    final run = Directory('${temporary.path}/custom logs/$name');
    await run.create(recursive: true);
    return run;
  }

  test('CLI help and grammar expose scoped greetd-test operations', () async {
    final dart = getDartCommand(Directory.current);
    for (final target in [
      '',
      'install',
      'start',
      'restore',
      'status',
      'logs',
    ]) {
      final result = await Process.run(dart.first, [
        ...dart.skip(1),
        'tool/akari.dart',
        'greetd-test',
        if (target.isNotEmpty) target,
        '--help',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('Usage: akari greetd-test'));
      expect(
        result.stdout,
        target == 'install'
            ? contains('-t, --theme')
            : isNot(contains('--theme')),
      );
      expect(result.stdout, isNot(contains('--report')));
      if (target == 'start') {
        expect(result.stdout, contains('--scale'));
        expect(result.stdout, contains('--log-dir'));
      }
    }
    for (final arguments in [
      ['start', '--theme', 'themes/default'],
      ['restore', '--scale', '2'],
      ['logs', '--run', 'unknown'],
      ['logs', '--lines', '0'],
    ]) {
      expect((await runFixture(arguments)).exitCode, 2);
    }
  });

  test('install forwards theme paths literally through sudo', () async {
    const theme = r'theme with $(touch unexpected)';
    for (final options in [
      ['--theme', theme],
      ['-t', theme],
      ['--theme=$theme'],
    ]) {
      final result = await runFixture(['install', ...options]);
      expect(result.exitCode, 17, reason: '${result.stderr}');
      expect(
        jsonDecode(await File('${temporary.path}/calls.json').readAsString()),
        [
          '--',
          'bash',
          '${Directory.current.path}/scripts/greetd-test/install.sh',
          installation.path,
          '${temporary.path}/$theme',
        ],
      );
    }
    expect(File('${temporary.path}/unexpected').existsSync(), isFalse);
    expect(Directory('${temporary.path}/build').existsSync(), isFalse);
  });

  test(
    'start normalizes paths and forwards literal options through sudo',
    () async {
      final result = await runFixture([
        'start',
        '--scale=1.5',
        '--log-dir',
        r'logs with $(touch unexpected)',
      ]);
      expect(result.exitCode, 17, reason: '${result.stderr}');
      expect(
        jsonDecode(await File('${temporary.path}/calls.json').readAsString()),
        [
          '--',
          'bash',
          '${installation.path}/start.sh',
          '--scale',
          '1.5',
          '--log-dir',
          '${temporary.path}/logs with \$(touch unexpected)',
        ],
      );
      expect(File('${temporary.path}/unexpected').existsSync(), isFalse);
      expect(Directory('${temporary.path}/build').existsSync(), isFalse);
    },
  );

  test(
    'top-level dispatch bypasses development state for lifecycle commands',
    () async {
      final dart = getDartCommand(Directory.current);
      for (final target in ['install', 'start', 'restore']) {
        final result = await Process.run(
          dart.first,
          [
            ...dart.skip(1),
            '${Directory.current.path}/tool/akari.dart',
            'greetd-test',
            target,
            if (target == 'install') ...['--theme', 'relative theme'],
            if (target == 'start') ...[
              '--scale',
              '1.5',
              '--log-dir',
              'relative logs',
            ],
            '--dry-run',
          ],
          workingDirectory: temporary.path,
          environment: {'PATH': '${bin.path}:${Platform.environment['PATH']}'},
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final plan =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        expect(plan['command'], 'greetd-test $target');
        if (target == 'install') {
          expect(
            (plan['invocation'] as List).last,
            '${temporary.path}/relative theme',
          );
        }
        if (target == 'start') {
          expect(
            plan['invocation'],
            contains('${temporary.path}/relative logs'),
          );
        }
      }
      expect(Directory('${temporary.path}/build').existsSync(), isFalse);
    },
  );

  test('dry runs do not request privilege and install preserves SDK overrides', () async {
    for (final target in ['install', 'start', 'restore']) {
      final result = await runFixture(
        [target, '--dry-run'],
        environment: {'AKARI_DART_BIN': 'SDK with spaces/bin/dart'},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final plan = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(plan['dry_run'], isTrue);
      if (target == 'install') {
        expect(
          plan['invocation'],
          contains(
            'AKARI_DART_BIN=${Directory.current.path}/SDK with spaces/bin/dart',
          ),
        );
        expect((plan['invocation'] as List).last, installation.path);
      }
    }
    expect(File('${temporary.path}/calls.json').existsSync(), isFalse);
  });

  test('root lifecycle calls do not request sudo again', () async {
    final result = await runFixture(
      ['restore', '--dry-run'],
      environment: {'FAKE_UID': '0'},
    );
    expect(result.exitCode, 0);
    final plan = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(plan['invocation'], ['bash', '${installation.path}/restore.sh']);
  });

  test(
    'logs distinguish rejected attempts from armed tests in custom locations',
    () async {
      final current = await createRun('armed');
      final latest = await createRun('rejected');
      await File('${current.path}/start.log').writeAsString('armed test\n');
      await File('${latest.path}/start.log')
          .writeAsString('rejected attempt\n');
      await Link('${installation.path}/current-run').create(current.path);
      await Link('${installation.path}/latest-run-1000').create(latest.path);
      final latestLogs = await runFixture(['logs']);
      expect(latestLogs.exitCode, 0, reason: '${latestLogs.stderr}');
      expect(latestLogs.stdout, 'rejected attempt\n');
      final currentLogs = await runFixture(['logs', '--run', 'current']);
      expect(currentLogs.exitCode, 0, reason: '${currentLogs.stderr}');
      expect(currentLogs.stdout, 'armed test\n');
      final status = await runFixture(['status', '--format', 'json']);
      expect(status.exitCode, 0, reason: '${status.stderr}');
      final report =
          jsonDecode(status.stdout as String) as Map<String, dynamic>;
      expect(report['latest_run'], latest.path);
      expect(report['current_run'], current.path);
      expect((report['units'] as List)[1]['LoadState'], 'not-found');
      expect(File('${temporary.path}/calls.json').existsSync(), isFalse);
    },
  );

  test('session logs select the newest greeter session without overwriting history', () async {
    final run = await createRun('armed');
    await Link('${installation.path}/current-run').create(run.path);
    final old = Directory('${run.path}/greeter/session-old');
    final newest = Directory('${run.path}/greeter/session-new');
    await old.create(recursive: true);
    await newest.create();
    await File('${old.path}/backend.log').writeAsString('old backend\n');
    await File('${newest.path}/backend.log').writeAsString('new backend\n');
    await Process.run('touch', ['-d', '2020-01-01', old.path]);
    final result = await runFixture([
      'logs',
      '--run',
      'current',
      '--file',
      'backend',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, 'new backend\n');
    expect(
      await File('${old.path}/backend.log').readAsString(),
      'old backend\n',
    );
    expect(
      getGreetdTestLogFile(
        installation,
        '1000',
        run: 'current',
        log: 'backend',
      ).path,
      '${newest.path}/backend.log',
    );
  });

  test('missing logs and failed systemd connection remain visible', () async {
    final logs = await runFixture(['logs']);
    expect(logs.exitCode, 1);
    expect(logs.stderr, contains('No latest test logs found'));
    final status = await runFixture(
      ['status'],
      environment: {'FAIL_SYSTEMD': '1'},
    );
    expect(status.exitCode, 1);
    expect(status.stderr, contains('Failed to connect to systemd'));
  });
}
