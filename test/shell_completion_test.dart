import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/cli_install.dart';
import '../tool/src/shell_completion.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mozais-shell-test-');
  });
  tearDown(() => temp.delete(recursive: true));

  Future<List<String>> completeBashWords(List<String> words) async {
    final completion = File('${temp.path}/completion.bash');
    await completion.writeAsString(getShellCompletion('bash'));
    final result = await Process.run('bash', [
      '--noprofile',
      '--norc',
      '-c',
      '''
source ${_quote(completion.path)}
COMP_WORDS=(${words.map(_quote).join(' ')})
COMP_CWORD=${words.length - 1}
_mozais
printf '%s\\0' "\${COMPREPLY[@]}"
''',
    ], workingDirectory: temp.path);
    expect(result.exitCode, 0, reason: result.stderr);
    return (result.stdout as String)
        .split('\x00')
        .where((word) => word.isNotEmpty)
        .toList();
  }

  test('bash completes commands, scoped options and enum values', () async {
    expect(await completeBashWords(['mozais', 'tr']), ['trace-perf', 'trace']);
    expect(await completeBashWords(['mozais', 'st']), isEmpty);
    expect(await completeBashWords(['mozais', 'run', 'st']), ['studio']);
    expect(await completeBashWords(['mozais', 'run', '']), ['studio']);
    expect(await completeBashWords(['mozais', 'greetd-test', '']), [
      'install',
      'start',
      'restore',
      'status',
      'logs',
    ]);
    expect(await completeBashWords(['mozais', 'greetd-test', 'start', '--l']), [
      '--log-dir',
    ]);
    expect(
      await completeBashWords(['mozais', 'greetd-test', 'logs', '--run', 'c']),
      ['current'],
    );
    final studioOptions = await completeBashWords([
      'mozais',
      'run',
      'studio',
      '',
    ]);
    expect(studioOptions, containsAll(['-t', '--theme', '-j', '--jobs']));
    expect(studioOptions, isNot(contains('--backend')));
    expect(studioOptions, isNot(contains('--mode')));
    final options = await completeBashWords(['mozais', 'verify', '']);
    expect(options, containsAll(['-t', '--theme', '--format']));
    expect(options, isNot(contains('--mode')));
    expect(options, isNot(contains('--jobs')));
    expect(await completeBashWords(['mozais', 'build', '-m', 'pr']), [
      'profile',
    ]);
    expect(await completeBashWords(['mozais', 'run', '--backend', 're']), [
      'real',
    ]);
    expect(await completeBashWords(['mozais', 'build', '--mode=pr']), [
      '--mode=profile',
    ]);
    expect(await completeBashWords(['mozais', 'build', '--mode', '=', 'pr']), [
      'profile',
    ]);
    expect(
      await completeBashWords(['mozais', 'perf', '--', '-m', 'pr']),
      isEmpty,
    );
    expect(await completeBashWords(['mozais', 'trace', '--', '']), isEmpty);
  });

  test('bash preserves spaces in directory and file matches', () async {
    await Directory('${temp.path}/theme with spaces').create();
    await File('${temp.path}/report with spaces.json').writeAsString('{}');
    expect(await completeBashWords(['mozais', 'build', '-t', 'theme']), [
      'theme with spaces',
    ]);
    expect(await completeBashWords(['mozais', 'build', '--theme=theme']), [
      '--theme=theme with spaces',
    ]);
    expect(
      await completeBashWords(['mozais', 'run', 'studio', '--theme=theme']),
      ['--theme=theme with spaces'],
    );
    expect(
      await completeBashWords(['mozais', 'verify', '--report', 'report']),
      ['report with spaces.json'],
    );
    expect(
      await completeBashWords(['mozais', 'verify', '-t', 'report']),
      isEmpty,
    );
  });

  test('zsh completes through the real line editor', () async {
    final completion = File('${temp.path}/completion.zsh');
    await completion.writeAsString(getShellCompletion('zsh'));
    await Directory('${temp.path}/theme with spaces').create();
    final result = await Process.run('python3', [
      '${Directory.current.path}/test/support/zsh_completion_probe.py',
      completion.path,
      temp.path,
    ]);
    expect(result.exitCode, 0, reason: result.stderr);
    final buffers = (jsonDecode(result.stdout as String) as List)
        .cast<String>();
    expect(buffers.map((value) => value.trimRight()).take(5), [
      'mozais trace',
      'mozais build -m profile',
      'mozais run --backend real',
      'mozais perf -- --mode pr',
      'mozais build --mode=profile',
    ]);
    expect(buffers[5].trimRight(), 'mozais run studio');
    expect(buffers[6].trimRight(), 'mozais run studio --theme=');
    expect(
      buffers[7].trimRight(),
      r'mozais run studio -t theme\ with\ spaces/',
    );
    expect(buffers[8].trimRight(), r'mozais build -t theme\ with\ spaces/');
    expect(buffers[9].trimRight(), 'mozais greetd-test restore');
    expect(buffers[10].trimRight(), 'mozais greetd-test start --log-dir=');
    expect(buffers[11].trimRight(), 'mozais greetd-test logs --run current');
  });

  test('installation preserves startup content and works outside the repository', () async {
    final prefix = Directory('${temp.path}/prefix with spaces and \' quote');
    final rc = File('${temp.path}/.bashrc');
    await rc.writeAsString('# existing configuration\n');
    for (var index = 0; index < 2; index++) {
      await installCli(
        repoRoot: Directory.current,
        prefix: prefix,
        rcFile: rc,
        shell: 'bash',
      );
    }
    final startup = await rc.readAsString();
    expect(startup, startsWith('# existing configuration\n'));
    expect('if [ -f'.allMatches(startup), hasLength(1));
    final project = Directory('${temp.path}/relative theme');
    await Directory('${project.path}/lib').create(recursive: true);
    await File('${project.path}/pubspec.yaml')
        .writeAsString('name: theme_ocean\n');
    await File('${project.path}/lib/theme.dart')
        .writeAsString('buildOceanTheme() {}');
    await File('${project.path}/lib/ocean.scene.json').writeAsString('{}');
    final result = await Process.run(
      '${prefix.path}/bin/mozais',
      ['build', '-t', 'relative theme', '-m', 'debug', '--dry-run'],
      workingDirectory: temp.path,
      environment: {
        'MOZAIS_DART_BIN':
            '${Directory.current.path}/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart',
      },
    );
    expect(result.exitCode, 0, reason: result.stderr);
    final plan = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(plan['command'], 'build');
    expect((plan['steps'] as List)[1]['working_directory'], project.path);
    final studio = await Process.run(
      '${prefix.path}/bin/mozais',
      ['run', 'studio', '-t', 'relative theme', '--dry-run'],
      workingDirectory: temp.path,
      environment: {
        'MOZAIS_DART_BIN':
            '${Directory.current.path}/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart',
      },
    );
    expect(studio.exitCode, 0, reason: studio.stderr);
    final studioPlan =
        jsonDecode(studio.stdout as String) as Map<String, dynamic>;
    expect(studioPlan['command'], 'run studio');
    expect((studioPlan['steps'] as List).last['id'], 'theme.studio');
    expect(studioPlan['artifacts']['host_project'], endsWith('/studio'));
    final activation = await Process.run('bash', [
      '--noprofile',
      '--norc',
      '-c',
      '. ${_quote(rc.path)}; command -v mozais; complete -p mozais',
    ]);
    expect(activation.exitCode, 0, reason: activation.stderr);
    expect(activation.stdout, contains('${prefix.path}/bin/mozais'));
    expect(activation.stdout, contains('-F _mozais mozais'));
  });

  test('zsh environment registers completion and syntax checks pass', () async {
    final prefix = Directory('${temp.path}/prefix');
    final rc = File('${temp.path}/.zshrc');
    await installCli(
      repoRoot: Directory.current,
      prefix: prefix,
      rcFile: rc,
      shell: 'zsh',
    );
    final result = await Process.run(
      'zsh',
      [
        '-f',
        '-c',
        '. ${_quote(rc.path)}; print -r -- \$_comps[mozais]; command -v mozais',
      ],
      environment: {'HOME': temp.path, 'ZDOTDIR': temp.path},
    );
    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, contains('_mozais'));
    expect(result.stdout, contains('${prefix.path}/bin/mozais'));
    for (final shell in ['bash', 'zsh']) {
      final file = File('${temp.path}/syntax.$shell');
      await file.writeAsString(getShellCompletion(shell));
      final check = await Process.run(shell, ['-n', file.path]);
      expect(check.exitCode, 0, reason: check.stderr);
    }
  });

  test('installation refuses to overwrite an unrelated command', () async {
    final prefix = Directory('${temp.path}/prefix');
    final launcher = File('${prefix.path}/bin/mozais');
    await launcher.parent.create(recursive: true);
    await launcher.writeAsString('unrelated command');
    final rc = File('${temp.path}/.bashrc');
    await expectLater(
      installCli(
        repoRoot: Directory.current,
        prefix: prefix,
        rcFile: rc,
        shell: 'bash',
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await launcher.readAsString(), 'unrelated command');
    expect(await rc.exists(), isFalse);
  });
}

String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
