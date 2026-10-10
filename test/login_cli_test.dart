import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/sdk_commands.dart';

void main() {
  late Directory temporary;
  late Directory installation;
  late Directory bin;
  late File runner;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('akari-login-cli-');
    installation = Directory('${temporary.path}/installation with spaces');
    bin = Directory('${temporary.path}/bin');
    await installation.create();
    await bin.create();
    await File('${installation.path}/manage.py').writeAsString('fixture');
    final python = (await Process.run('which', [
      'python3',
    ])).stdout.toString().trim();
    final boundary = File('${bin.path}/boundary');
    await boundary.writeAsString('''#!$python
import json, os, pathlib, sys
root = pathlib.Path(os.environ['FIXTURE'])
command = pathlib.Path(sys.argv[0]).name
if command == 'id':
    print(os.environ.get('FAKE_UID', '1000'))
elif command == 'sudo':
    (root / 'sudo.json').write_text(json.dumps(sys.argv[1:]))
    sys.exit(17)
elif command == 'builder':
    (root / 'build.json').write_text(json.dumps(sys.argv[1:]))
    if os.environ.get('FAIL_BUILD'):
        print('build failed before deployment', file=sys.stderr)
        sys.exit(23)
    print(json.dumps({'status': 'passed', 'report_path': 'build/report.json',
                     'artifacts': {'executable': 'fixture bundle/greeter',
                                   'backend_executable': 'fixture backend'}}))
elif command == 'python3':
    if sys.argv[1].endswith('display-layout.py'):
        sys.exit(1)
    (root / 'query.json').write_text(json.dumps(sys.argv[1:]))
    print('controller query')
''');
    expect((await Process.run('chmod', ['+x', boundary.path])).exitCode, 0);
    for (final name in ['id', 'sudo', 'builder', 'python3']) {
      await Link('${bin.path}/$name').create(boundary.path);
    }
    runner = File('${temporary.path}/runner.dart');
    await runner.writeAsString('''
import 'dart:io';
import '${Directory.current.uri}tool/src/login.dart';
import '${Directory.current.uri}tool/src/cli_definition.dart';
Future<void> main(List<String> arguments) async {
  try {
    final name = ['install', 'uninstall'].contains(arguments.first)
        ? arguments.first : 'login ' + arguments.first;
    exitCode = await runLoginCommand(getCliCommand(name), arguments.skip(1).toList(),
      repoRoot: Directory(Platform.environment['REPOSITORY']!),
      installation: Directory(Platform.environment['INSTALLATION']!));
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
        'FIXTURE': temporary.path,
        'REPOSITORY': Directory.current.path,
        'INSTALLATION': installation.path,
        'AKARI_DART_BIN': '${bin.path}/builder',
        ...environment,
      },
    );
  }

  test(
    'production workflow tests isolate systemd and runtime boundaries',
    () async {
      final result = await Process.run('python3', [
        '${Directory.current.path}/test/support/login_workflow_test.py',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test(
    'install builds release before sudo and preserves literal paths',
    () async {
      const theme = r'theme with $(touch unexpected)';
      final result = await runFixture(['install', '-t', theme, '-j', '2']);
      expect(result.exitCode, 17, reason: '${result.stderr}');
      expect(
        jsonDecode(await File('${temporary.path}/build.json').readAsString()),
        [
          '${Directory.current.path}/tool/akari.dart',
          'build',
          '--theme',
          '${temporary.path}/$theme',
          '--mode',
          'release',
          '--platform',
          'linux',
          '--jobs',
          '2',
          '--format',
          'json',
        ],
      );
      expect(
        jsonDecode(await File('${temporary.path}/sudo.json').readAsString()),
        [
          '--',
          'python3',
          '${Directory.current.path}/scripts/login/manage.py',
          'install',
          '--keyring',
          'auto',
          '--source',
          Directory.current.path,
          '--bundle',
          '${Directory.current.path}/fixture bundle',
          '--backend',
          '${Directory.current.path}/fixture backend',
        ],
      );
      expect(File('${temporary.path}/unexpected').existsSync(), isFalse);
    },
  );

  test('build failure prevents privileged deployment', () async {
    final result = await runFixture(
      ['install'],
      environment: {'FAIL_BUILD': '1'},
    );
    expect(result.exitCode, 23);
    expect(result.stderr, contains('build failed before deployment'));
    expect(File('${temporary.path}/sudo.json').existsSync(), isFalse);
  });

  test('explicit keyring selection reaches privileged controller', () async {
    final result = await runFixture(['install', '--keyring', 'gnome']);
    expect(result.exitCode, 17, reason: '${result.stderr}');
    final invocation = jsonDecode(
      await File('${temporary.path}/sudo.json').readAsString(),
    ) as List;
    expect(invocation, containsAllInOrder(['install', '--keyring', 'gnome']));
    final dryRun = await runFixture([
      'install',
      '--keyring',
      'kwallet',
      '--dry-run',
    ]);
    expect(dryRun.exitCode, 0);
    expect(
      (jsonDecode(dryRun.stdout as String) as Map)['invocation'],
      containsAllInOrder(['install', '--keyring', 'kwallet']),
    );
  });

  test('dry runs never build or request privilege', () async {
    for (final target in [
      'install',
      'enable',
      'disable',
      'rollback',
      'uninstall',
    ]) {
      final result = await runFixture([target, '--dry-run']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final plan = jsonDecode(result.stdout as String) as Map;
      expect(plan['dry_run'], isTrue);
      expect((plan['invocation'] as List).first, 'sudo');
      if (target == 'install') {
        expect(
          plan['build'],
          containsAllInOrder(['--mode', 'release', '--jobs', '4']),
        );
      }
    }
    expect(File('${temporary.path}/build.json').existsSync(), isFalse);
    expect(File('${temporary.path}/sudo.json').existsSync(), isFalse);
    expect(Directory('${temporary.path}/build').existsSync(), isFalse);
  });

  test(
    'lifecycle uses installed controller and root does not request sudo',
    () async {
      final result = await runFixture(['enable']);
      expect(result.exitCode, 17);
      expect(
        jsonDecode(await File('${temporary.path}/sudo.json').readAsString()),
        ['--', 'python3', '${installation.path}/manage.py', 'enable'],
      );
      final root = await runFixture(
        ['disable', '--dry-run'],
        environment: {'FAKE_UID': '0'},
      );
      expect(root.exitCode, 0);
      expect((jsonDecode(root.stdout as String) as Map)['invocation'], [
        'python3',
        '${installation.path}/manage.py',
        'disable',
      ]);
      final rootInstall = await runFixture(
        ['install'],
        environment: {'FAKE_UID': '0'},
      );
      expect(rootInstall.exitCode, 2);
      expect(rootInstall.stderr, contains('regular user'));
      expect(File('${temporary.path}/build.json').existsSync(), isFalse);
    },
  );

  test(
    'status and logs query without sudo, including before installation',
    () async {
      for (final installed in [true, false]) {
        if (!installed) await File('${installation.path}/manage.py').delete();
        for (final arguments in [
          ['status', '--format', 'json'],
          ['logs', '--component', 'backend', '-n', '20', '-f'],
        ]) {
          final result = await runFixture(arguments);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          final invocation = jsonDecode(
            await File('${temporary.path}/query.json').readAsString(),
          ) as List;
          expect(
            invocation.first,
            installed
                ? '${installation.path}/manage.py'
                : '${Directory.current.path}/scripts/login/manage.py',
          );
          if (arguments.first == 'logs') {
            expect(
              invocation,
              containsAllInOrder([
                '--component',
                'backend',
                '--lines',
                '20',
                '--follow',
              ]),
            );
          }
        }
      }
      expect(File('${temporary.path}/sudo.json').existsSync(), isFalse);
    },
  );

  test('invalid production options fail before external operations', () async {
    for (final arguments in [
      ['install', '--shell', 'zsh'],
      ['install', '-j', '0'],
      ['install', '--mode', 'debug'],
      ['install', '--keyring', 'other'],
      ['enable', '--keyring', 'gnome'],
      ['enable', '--theme', 'themes/default'],
      ['logs', '--lines', '0'],
      ['logs', '--component', 'unknown'],
    ]) {
      final result = await runFixture(arguments);
      expect(result.exitCode, 2, reason: '$arguments: ${result.stderr}');
    }
    expect(File('${temporary.path}/build.json').existsSync(), isFalse);
    expect(File('${temporary.path}/sudo.json').existsSync(), isFalse);
    expect(File('${temporary.path}/query.json').existsSync(), isFalse);
  });

  test(
    'top-level help and dispatch expose production and shell installations',
    () async {
      final dart = getDartCommand(Directory.current);
      for (final words in [
        ['install'],
        ['install', 'cli'],
        ['uninstall'],
        ['login'],
        ['login', 'enable'],
        ['login', 'disable'],
        ['login', 'rollback'],
        ['login', 'status'],
        ['login', 'logs'],
      ]) {
        final help = await Process.run(dart.first, [
          ...dart.skip(1),
          '${Directory.current.path}/tool/akari.dart',
          ...words,
          '--help',
        ]);
        expect(help.exitCode, 0, reason: '${help.stderr}');
        expect(help.stdout, contains('Usage: akari ${words.join(' ')}'));
        expect(help.stdout, isNot(contains('--report')));
      }
      for (final words in [
        ['install'],
        ['uninstall'],
        ['login', 'enable'],
      ]) {
        final result = await Process.run(dart.first, [
          ...dart.skip(1),
          '${Directory.current.path}/tool/akari.dart',
          ...words,
          '--dry-run',
        ], workingDirectory: temporary.path);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          (jsonDecode(result.stdout as String) as Map)['command'],
          words.join(' '),
        );
      }
      expect(Directory('${temporary.path}/build').existsSync(), isFalse);
    },
  );
}
