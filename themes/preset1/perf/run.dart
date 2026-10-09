import 'dart:convert';
import 'dart:io';

import '../../../tool/src/sdk_commands.dart';
import '../../../tool/src/theme_host.dart';
import '../../../tool/src/theme_project.dart';

/// Run the performance journey in the same nested Sway environment as preview.
/// The compositor report is retained alongside frame metrics so a result cannot
/// silently describe the host desktop's different scale or software renderer.
Future<void> main() async {
  final output = Directory(Platform.environment['AKARI_PERF_OUTPUT_DIR']!);
  final directory = File.fromUri(Platform.script).parent.parent;
  final root = directory.parent.parent;
  final theme = getThemePackage(directory);
  final host = Directory(
    '${root.path}/${getThemeHostDirectory(theme, preview: true)}-perf',
  );
  createThemeHost(
    repoRoot: root,
    theme: theme,
    output: host,
    preview: true,
    devDependencies: {
      'flutter_test': {'sdk': 'flutter'},
      'integration_test': {'sdk': 'flutter'},
    },
  );
  final flutter = getFlutterCommand(root);
  if (await _execute([...flutter, 'pub', 'get'], host) != 0) {
    exitCode = 1;
    return;
  }
  final profile = await Process.run('python3', [
    '${root.path}/scripts/greetd-test/display_profile.py',
    '--reference',
    '${root.path}/config/sway/reference.json',
    '--state',
    '${output.path}/display-state',
    '--display-profile',
    'reference',
    '--dry-run',
  ]);
  if (profile.exitCode != 0) {
    stderr.write(profile.stderr);
    exitCode = profile.exitCode;
    return;
  }
  // Sway's Unix socket must fit sun_path (108 bytes). Perf run directories
  // are deeper than normal preview directories, so run the compositor in a
  // short temporary directory, then collect its artifacts with the metrics.
  final temporary = await Directory.systemTemp.createTemp('akari-p1-');
  late final int status;
  try {
    status = await _execute(
      [
        'python3',
        '${root.path}/scripts/sway-session.py',
        '--log-dir',
        '${temporary.path}/sway',
        '--backend',
        'wayland',
        '--',
        'dbus-run-session',
        '--',
        ...flutter,
        'drive',
        '-d',
        'linux',
        '--profile',
        '--no-dds',
        '--dart-define=AKARI_BACKEND=demo',
        '--dart-define=PRESET1_PERF_OUTPUT=${output.path}',
        '--driver=${directory.path}/perf/test_driver/integration_test.dart',
        '--target=${directory.path}/perf/integration_test/environment_test.dart',
      ],
      host,
      environment: {'AKARI_DISPLAY_PROFILE_JSON': profile.stdout as String},
    );
  } finally {
    await for (final entity in temporary.list(recursive: true)) {
      if (entity is File) {
        final target = File(
          '${output.path}/${entity.path.substring(temporary.path.length + 1)}',
        );
        await target.parent.create(recursive: true);
        await entity.copy(target.path);
      }
    }
    final displayReport = File('${output.path}/sway/display-report.json');
    if (displayReport.existsSync()) {
      final report = await displayReport.readAsString();
      await displayReport.writeAsString(
        report.replaceAll('${temporary.path}/', '${output.path}/'),
      );
    }
    await temporary.delete(recursive: true);
  }
  final artifacts = <Map<String, String>>[
    for (final name in [
      'report.json',
      'dormant.png',
      'dormant_rain.png',
      'login.png',
      'account_menu.png',
      'session_menu.png',
      'error.png',
      'sway/display-report.json',
    ])
      if (File('${output.path}/$name').existsSync())
        {'name': name, 'path': name},
  ];
  await File('${output.path}/result.json')
      .writeAsString(jsonEncode({'version': 1, 'artifacts': artifacts}));
  exitCode = status;
}

Future<int> _execute(
  List<String> command,
  Directory directory, {
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    command.first,
    command.skip(1).toList(),
    workingDirectory: directory.path,
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}
