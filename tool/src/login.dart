import 'dart:convert';
import 'dart:io';

import 'cli_definition.dart';
import 'sdk_commands.dart';

const loginInstallationPath = '/opt/akari';

Future<int> runLoginCommand(
  CliCommand command,
  List<String> arguments, {
  required Directory repoRoot,
  Directory? installation,
}) async {
  final values = getCliOptionValues(command, arguments);
  final root = installation ?? Directory(loginInstallationPath);
  final operation = command.name.split(' ').last;
  final query = operation == 'status' || operation == 'logs';
  final lines = int.tryParse(values['--lines'] ?? '100');
  if (operation == 'logs' && (lines == null || lines < 1)) {
    throw const FormatException('--lines must be a positive integer.');
  }
  final jobs = int.tryParse(values['--jobs'] ?? '4');
  if (operation == 'install' && (jobs == null || jobs < 1)) {
    throw const FormatException('--jobs must be a positive integer.');
  }
  final controller = File('${root.path}/manage.py');
  final script = operation == 'install' || (query && !controller.existsSync())
      ? File('${repoRoot.path}/scripts/login/manage.py')
      : controller;
  final privilege = <String>[];
  if (!query) {
    final identity = await Process.run('id', ['-u']);
    if (identity.exitCode != 0) {
      throw ProcessException(
        'id',
        ['-u'],
        '${identity.stderr}',
        identity.exitCode,
      );
    }
    if ((identity.stdout as String).trim() != '0') {
      privilege.addAll(['sudo', '--']);
    } else if (operation == 'install' && !values.containsKey('--dry-run')) {
      throw const FormatException(
        'Run akari install as your regular user. It builds without root and requests sudo only for deployment.',
      );
    }
  }
  final invocation = [
    ...privilege,
    'python3',
    script.path,
    operation,
    if (operation == 'install') ...['--keyring', values['--keyring'] ?? 'auto'],
    if (values.containsKey('--format')) ...['--format', values['--format']!],
    if (values.containsKey('--component')) ...[
      '--component',
      values['--component']!,
    ],
    if (operation == 'logs') ...['--lines', '$lines'],
    if (values.containsKey('--follow')) '--follow',
  ];
  final build = operation == 'install'
      ? [
          ...getDartCommand(repoRoot),
          '${repoRoot.path}/tool/akari.dart',
          'build',
          '--theme',
          Directory(values['--theme'] ?? '${repoRoot.path}/themes/default')
              .absolute
              .path,
          '--mode',
          'release',
          '--platform',
          'linux',
          '--jobs',
          '$jobs',
          '--format',
          'json',
        ]
      : null;
  if (values.containsKey('--dry-run')) {
    stdout.writeln(
      jsonEncode({
        'command': command.name,
        'dry_run': true,
        'build': ?build,
        'invocation': [
          ...invocation,
          if (build != null) ...[
            '--source',
            repoRoot.path,
            '--bundle',
            '<successful-build-bundle>',
            '--backend',
            '<successful-build-backend>',
          ],
        ],
      }),
    );
    return 0;
  }
  if (!script.existsSync()) {
    throw FileSystemException(
      'Production controller is missing; run akari install first',
      script.path,
    );
  }
  if (build == null) return _runInvocation(invocation);

  stderr.writeln('Building the production theme and backend without root...');
  final process = await Process.start(build.first, build.skip(1).toList());
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = stderr.addStream(process.stderr);
  final result = await process.exitCode;
  await errors;
  final reportText = await output;
  if (result != 0) {
    stderr.write(reportText);
    return result;
  }
  final report = jsonDecode(reportText) as Map<String, dynamic>;
  final artifacts = report['artifacts'] as Map<String, dynamic>;
  final bundle = File('${repoRoot.path}/${artifacts['executable']}').parent;
  final backend = File('${repoRoot.path}/${artifacts['backend_executable']}');
  stderr.writeln('Build report: ${repoRoot.path}/${report['report_path']}');
  final temporary = await Directory.systemTemp.createTemp('akari-login-');
  try {
    final capture = await Process.run('python3', [
      '${repoRoot.path}/scripts/greetd-test/display-layout.py',
      'capture',
    ]);
    File? layout;
    if (capture.exitCode == 0) {
      layout = File('${temporary.path}/display-layout.json');
      await layout.writeAsString(capture.stdout as String);
    } else {
      stderr.writeln(
        'No desktop display order captured; preserving any installed layout.',
      );
    }
    return await _runInvocation([
      ...invocation,
      '--source',
      repoRoot.path,
      '--bundle',
      bundle.path,
      '--backend',
      backend.path,
      if (layout != null) ...['--layout', layout.path],
    ]);
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<int> _runInvocation(List<String> invocation) async {
  final process = await Process.start(
    invocation.first,
    invocation.skip(1).toList(),
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}
