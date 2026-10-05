import 'dart:convert';
import 'dart:io';

import 'cli_definition.dart';

const greetdTestInstallationPath = '/opt/akari-test';

Future<int> runGreetdTestCommand(
  CliCommand command,
  List<String> arguments, {
  Directory? repoRoot,
  Directory? installation,
}) async {
  final values = getCliOptionValues(command, arguments);
  final root = installation ?? Directory(greetdTestInstallationPath);
  final identity = await Process.run('id', ['-u']);
  if (identity.exitCode != 0) {
    throw ProcessException(
      'id',
      ['-u'],
      '${identity.stderr}',
      identity.exitCode,
    );
  }
  final uid = (identity.stdout as String).trim();
  final callerUid = uid == '0' ? Platform.environment['SUDO_UID'] ?? uid : uid;

  if (command.name == 'greetd-test status') {
    final status = await getGreetdTestStatus(root, callerUid);
    if (values['--format'] == 'json') {
      stdout.writeln(jsonEncode(status));
    } else {
      stdout.writeln(
        'Installation: ${root.path} (${status['installed'] == true ? 'installed' : 'missing'})',
      );
      stdout.writeln('Latest attempt: ${status['latest_run'] ?? 'none'}');
      stdout.writeln('Last armed test: ${status['current_run'] ?? 'none'}');
      for (final unit in status['units'] as List<Map<String, String>>) {
        stdout.writeln(
          '${unit['Id']}: ${unit['LoadState']}, ${unit['ActiveState']}/${unit['SubState']}',
        );
      }
    }
    return 0;
  }
  if (command.name == 'greetd-test logs') {
    final lines = int.tryParse(values['--lines'] ?? '100');
    if (lines == null || lines < 1) {
      throw const FormatException('--lines must be a positive integer.');
    }
    final file = getGreetdTestLogFile(
      root,
      callerUid,
      run: values['--run'] ?? 'latest',
      log: values['--file'] ?? 'start',
    );
    stderr.writeln('Test log: ${file.path}');
    final process = await Process.start('tail', [
      '-n',
      '$lines',
      if (values.containsKey('--follow')) '-F',
      '--',
      file.path,
    ], mode: ProcessStartMode.inheritStdio);
    return process.exitCode;
  }
  final script = command.name == 'greetd-test install'
      ? File('${repoRoot!.path}/scripts/greetd-test/install.sh')
      : File('${root.path}/${command.name.split(' ').last}.sh');
  final scriptArguments = [
    if (command.name == 'greetd-test install') root.path,
    if (values.containsKey('--scale')) ...['--scale', values['--scale']!],
    if (values.containsKey('--log-dir')) ...[
      '--log-dir',
      Directory(values['--log-dir']!).absolute.path,
    ],
  ];
  // sudo filters SDK overrides. Forward only the installer's documented SDK
  // settings, resolving relative paths before it changes working directory.
  final sdkEnvironment = <String>[];
  if (command.name == 'greetd-test install') {
    for (final name in ['AKARI_FLUTTER_BIN', 'AKARI_DART_BIN']) {
      final value = Platform.environment[name];
      if (value != null && value.isNotEmpty) {
        final binary = File(value);
        sdkEnvironment.add(
          '$name=${binary.isAbsolute ? value : '${repoRoot!.path}/$value'}',
        );
      }
    }
  }
  final invocation = [
    if (uid != '0') ...['sudo', '--'],
    if (sdkEnvironment.isNotEmpty) ...['env', ...sdkEnvironment],
    'bash',
    script.path,
    ...scriptArguments,
  ];
  if (values.containsKey('--dry-run')) {
    stdout.writeln(
      jsonEncode({
        'command': command.name,
        'dry_run': true,
        'invocation': invocation,
      }),
    );
    return 0;
  }
  if (!script.existsSync()) {
    throw FileSystemException(
      'Test script is missing; run akari greetd-test install first',
      script.path,
    );
  }
  final process = await Process.start(
    invocation.first,
    invocation.skip(1).toList(),
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

Directory? findGreetdTestRun(
  Directory installation,
  String callerUid, {
  required String run,
}) {
  final pointer = Directory(
    '${installation.path}/${run == 'latest' ? 'latest-run-$callerUid' : 'current-run'}',
  );
  return pointer.existsSync()
      ? Directory(pointer.resolveSymbolicLinksSync())
      : null;
}

File getGreetdTestLogFile(
  Directory installation,
  String callerUid, {
  required String run,
  required String log,
}) {
  final directory = findGreetdTestRun(installation, callerUid, run: run);
  if (directory == null) {
    throw StateError(
      'No $run test logs found. Install the current harness and start a test first.',
    );
  }
  if (const {'start', 'restore', 'journal'}.contains(log)) {
    return File('${directory.path}/$log.log');
  }
  final greeter = Directory('${directory.path}/greeter');
  final sessions = greeter.existsSync()
      ? greeter
            .listSync()
            .whereType<Directory>()
            .where(
              (entry) => entry.path
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('session-'),
            )
            .toList()
      : <Directory>[];
  if (sessions.isEmpty) {
    throw StateError('No greeter session logs found in ${directory.path}.');
  }
  sessions.sort(
    (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
  );
  return File('${sessions.first.path}/$log.log');
}

Future<Map<String, Object?>> getGreetdTestStatus(
  Directory installation,
  String callerUid,
) async {
  const arguments = [
    'show',
    '--no-pager',
    '--property=Id,LoadState,ActiveState,SubState,Result',
    'sddm.service',
    'akari-test.service',
    'akari-restore.timer',
  ];
  final result = await Process.run('systemctl', arguments);
  final output = (result.stdout as String).trim();
  // Missing transient units are an ordinary status. A failed connection to
  // systemd has no unit properties and must remain visible as an error.
  if (result.exitCode != 0 && output.isEmpty) {
    throw ProcessException(
      'systemctl',
      arguments,
      '${result.stderr}',
      result.exitCode,
    );
  }
  return {
    'installation': installation.path,
    'installed': [
      'start.sh',
      'restore.sh',
      'launch.sh',
      'frontend/greeter',
      'backend',
    ].every((path) => File('${installation.path}/$path').existsSync()),
    'latest_run': findGreetdTestRun(
      installation,
      callerUid,
      run: 'latest',
    )?.path,
    'current_run': findGreetdTestRun(
      installation,
      callerUid,
      run: 'current',
    )?.path,
    'units': [
      for (final block in output.split('\n\n'))
        <String, String>{
          for (final line in block.split('\n'))
            if (line.contains('='))
              line.substring(0, line.indexOf('=')): line.substring(
                line.indexOf('=') + 1,
              ),
        },
    ],
  };
}
