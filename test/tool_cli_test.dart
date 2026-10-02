import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/command_plans.dart';
import '../tool/src/run_report.dart';
import '../tool/src/theme_project.dart';
import '../tool/src/theme_host.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mozais-tool-cli-test-');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test(
    'host synchronization preserves caches and unchanged file timestamps',
    () async {
      final project = await _createThemeProject(tempRoot);
      final theme = getThemePackage(project);
      final repository = Directory('${tempRoot.path}/repo');
      await Directory('${repository.path}/lib/app').create(recursive: true);
      await File('${repository.path}/lib/app/app.dart').writeAsString('first');
      await Directory('${repository.path}/linux/flutter')
          .create(recursive: true);
      final cmake = File('${repository.path}/linux/CMakeLists.txt');
      await cmake.writeAsString('cmake');
      await File('${repository.path}/pubspec.yaml').writeAsString(
        'version: 1.0.0\nenvironment: {sdk: ^3.13.2}\ndependencies: {dbus: ^0.7.11}\n',
      );
      final host = Directory('${tempRoot.path}/host');
      createThemeHost(
        repoRoot: repository,
        theme: theme,
        output: host,
        preview: true,
      );
      final manifest = File('${host.path}/pubspec.yaml');
      final originalModified = DateTime.utc(2020);
      await manifest.setLastModified(originalModified);
      await Directory('${host.path}/linux/flutter/ephemeral').create();
      await File('${host.path}/linux/flutter/ephemeral/cache')
          .writeAsString('cached');
      await Directory('${host.path}/build').create();
      await File('${host.path}/build/cache').writeAsString('cached');
      await File('${host.path}/linux/obsolete.cc').writeAsString('obsolete');
      await File('${repository.path}/lib/app/app.dart').writeAsString('second');
      createThemeHost(
        repoRoot: repository,
        theme: theme,
        output: host,
        preview: true,
      );
      expect((await manifest.lastModified()).toUtc(), originalModified);
      expect(
        await File('${host.path}/lib/app/app.dart').readAsString(),
        'second',
      );
      expect(File('${host.path}/linux/obsolete.cc').existsSync(), isFalse);
      expect(await File('${host.path}/build/cache').readAsString(), 'cached');
      expect(
        await File('${host.path}/linux/flutter/ephemeral/cache').readAsString(),
        'cached',
      );
      expect(
        getThemeHostDirectory(theme, preview: true),
        getThemeHostDirectory(getThemePackage(project), preview: true),
      );
      final otherProject = await _createThemeProject(
        Directory('${tempRoot.path}/other'),
      );
      expect(
        getThemeHostDirectory(theme, preview: true),
        isNot(
          getThemeHostDirectory(getThemePackage(otherProject), preview: true),
        ),
      );
    },
  );

  test(
    'build plans compile production backend and configure native jobs',
    () async {
      final project = await _createThemeProject(tempRoot);
      final plan = buildStepsFor(
        'build',
        3,
        Directory.current,
        'runs/build',
        buildTheme: getThemePackage(project),
        jobs: 4,
      );
      final backend = plan.singleWhere((step) => step.id == 'backend.build');
      expect(backend.command, containsAll(['--release', '--jobs', '4']));
      expect(backend.command, isNot(contains('mock')));
      final flutter = plan.singleWhere(
        (step) => step.id == 'flutter.build_linux',
      );
      expect(flutter.environment['MOZAIS_BUILD_JOBS'], '4');
      expect(backend.dependencies, isEmpty);
      expect(
        plan.singleWhere((step) => step.id == 'theme.pub_get').dependencies,
        isEmpty,
      );
    },
  );

  test(
    'independent steps overlap and dependents wait for both branches',
    () async {
      final gate = File('${tempRoot.path}/gate.py');
      await gate.writeAsString("""import pathlib, sys, time
name, other = sys.argv[1:]
pathlib.Path(name).touch()
for _ in range(500):
    if pathlib.Path(other).exists():
        sys.exit(0)
    time.sleep(0.01)
sys.exit(1)
""");
      final status = await runDevCommand(
        command: 'build',
        format: RunOutputFormat.json,
        reportPath: null,
        repoRoot: tempRoot,
        runDirectory: 'runs/concurrent',
        steps: [
          RunStep(
            id: 'left',
            command: ['python3', gate.path, 'left.ready', 'right.ready'],
            workingDirectory: '.',
            environment: const {},
            dependencies: const [],
          ),
          RunStep(
            id: 'right',
            command: ['python3', gate.path, 'right.ready', 'left.ready'],
            workingDirectory: '.',
            environment: const {},
            dependencies: const [],
          ),
          RunStep(
            id: 'join',
            command: [
              'bash',
              '-c',
              'test -f left.ready && test -f right.ready',
            ],
            workingDirectory: '.',
            environment: const {},
            dependencies: const ['left', 'right'],
          ),
        ],
        artifactPaths: const {},
      );
      expect(status, 0);
    },
  );

  test('discovers themes without required built-in names', () async {
    final themesDirectory = Directory('${tempRoot.path}/themes');
    final project = await _createThemeProject(themesDirectory);

    final themes = findThemePackages(tempRoot);

    expect(themes, hasLength(1));
    expect(themes.single.packageName, 'theme_ocean');
    expect(themes.single.directory.path, project.path);
  });

  test('rejects duplicate theme package names', () async {
    final themesDirectory = Directory('${tempRoot.path}/themes');
    await _createThemeProject(themesDirectory);
    final duplicate = await _createThemeProject(
      Directory('${tempRoot.path}/duplicate'),
    );
    await duplicate.rename('${themesDirectory.path}/another theme');

    expect(() => findThemePackages(tempRoot), throwsStateError);
  });

  test('verification plans discover independent theme projects', () async {
    await _createThemeProject(Directory('${tempRoot.path}/themes'));

    final steps = buildStepsFor('verify', 3, tempRoot, 'runs/verify');

    expect(
      steps
          .where((step) => step.id.startsWith('scenes.generate_'))
          .map((step) => step.id),
      ['scenes.generate_theme_ocean'],
    );
    expect(
      steps
          .where((step) => step.id.endsWith('.analyze'))
          .map((step) => step.id),
      unorderedEquals([
        'flutter.analyze',
        'scene_schema.analyze',
        'scene_codegen.analyze',
        'scene.analyze',
        'greeter_ui.analyze',
        'greeter_components.analyze',
        'theme_sdk.analyze',
        'theme_ocean.analyze',
      ]),
    );
  });

  test('build plans use theme metadata outside the repository', () async {
    final project = await _createThemeProject(tempRoot);
    final result = await _runTool([
      'build',
      '--theme',
      project.path,
      '--preview',
      '--dry-run',
    ]);
    expect(result.exitCode, 0, reason: result.stderr);
    final plan = jsonDecode(result.stdout) as Map<String, dynamic>;
    final steps = (plan['steps'] as List).cast<Map<String, dynamic>>();
    expect(steps.first['working_directory'], project.path);
    expect(steps[1]['id'], 'scenes.generate_theme_ocean');
    final build = steps.singleWhere(
      (step) => step['id'] == 'flutter.build_linux',
    );
    expect(build['command'], contains('--debug'));
    expect(build['command'], contains('--dart-define=MOZAIS_BACKEND=demo'));
    expect(steps.last['id'], 'theme.preview');
    expect(
      (steps.last['command'] as List).single,
      endsWith('/debug/bundle/greeter'),
    );
    expect(
      Directory('${Directory.current.path}/${plan['run_directory']}')
          .existsSync(),
      isFalse,
    );
  });

  test('preview options reject unsupported commands and platforms', () async {
    for (final arguments in [
      ['verify', '--preview'],
      ['build', '--preview', '--platform', 'web'],
      ['build', '--theme', 'themes/default', '--theme', 'themes/fallback'],
    ]) {
      final result = await _runTool(arguments);
      expect(result.exitCode, 2, reason: '$arguments: ${result.stderr}');
    }
  });

  test(
    'build launches an external theme using only its selected theme dependency',
    () async {
      final project = await _createThemeProject(tempRoot);
      final platformManifest = File('pubspec.yaml');
      final manifestBefore = await platformManifest.readAsString();
      final launchMarker = File('${tempRoot.path}/preview-started');
      final flutter = File('${tempRoot.path}/flutter');
      final dart = File('${tempRoot.path}/dart');
      final preview = File('${tempRoot.path}/preview');
      await preview.writeAsString(
        '#!/bin/sh\nprintf launched > ${_shellQuote(launchMarker.path)}\n',
      );
      await flutter.writeAsString('''#!/bin/sh
if [ "\$1" = build ]; then
  mkdir -p build/linux/x64/debug/bundle
  cp ${_shellQuote(preview.path)} build/linux/x64/debug/bundle/greeter
fi
''');
      final dartCommand = getDartCommand(Directory.current);
      await dart.writeAsString('''#!/bin/sh
if [ "\$1" = run ] && [ "\$2" = build_runner ]; then
  exit 0
fi
exec ${dartCommand.map(_shellQuote).join(' ')} "\$@"
''');
      final chmod = await Process.run('chmod', [
        '+x',
        flutter.path,
        dart.path,
        preview.path,
      ]);
      expect(chmod.exitCode, 0, reason: chmod.stderr);
      final result = await _runTool(
        ['build', '--theme', project.path, '--preview', '--format', 'json'],
        environment: {
          'MOZAIS_FLUTTER_BIN': flutter.path,
          'MOZAIS_DART_BIN': dart.path,
        },
      );
      expect(result.exitCode, 0, reason: result.stderr);
      final report = jsonDecode(result.stdout) as Map<String, dynamic>;
      final runDirectory = Directory(
        '${Directory.current.path}/${report['artifacts']['run_directory']}',
      );
      addTearDown(() => runDirectory.delete(recursive: true));
      expect(report['status'], 'passed');
      expect(await launchMarker.readAsString(), 'launched');
      expect(await platformManifest.readAsString(), manifestBefore);
      final host = Directory(
        '${Directory.current.path}/${report['artifacts']['host_project']}',
      );
      addTearDown(() => host.delete(recursive: true));
      final hostManifest = jsonDecode(
        await File('${host.path}/pubspec.yaml').readAsString(),
      ) as Map<String, dynamic>;
      expect(hostManifest['dependencies']['theme_ocean']['path'], project.path);
      expect(
        hostManifest['dependencies'].keys,
        unorderedEquals([
          'flutter',
          'dbus',
          'greeter_ui',
          'theme_sdk',
          'theme_ocean',
        ]),
      );
      final entrypoint = await File('${host.path}/lib/main.dart')
          .readAsString();
      expect(entrypoint, contains('themeBuilder: buildOceanTheme'));
      expect(entrypoint, isNot(contains('FileSessionStore')));
    },
  );

  test(
    'json format writes only the machine-readable run report to stdout',
    () async {
      final fakeDart = File('${tempRoot.path}/dart');
      await fakeDart.writeAsString(
        '#!/bin/sh\nprintf "fake sdk stdout\\n"\nprintf "fake sdk stderr\\n" >&2\n',
      );
      final chmod = await Process.run('chmod', ['+x', fakeDart.path]);
      expect(chmod.exitCode, 0, reason: chmod.stderr.toString());

      final result = await _runTool(
        ['generate-scenes', '--format', 'json'],
        environment: {'MOZAIS_DART_BIN': fakeDart.path},
      );
      expect(result.exitCode, 0, reason: result.stderr);
      final report = jsonDecode(result.stdout) as Map<String, dynamic>;
      expect(report['command'], 'generate-scenes');
      expect(report['status'], 'passed');
      final runDirectory =
          (report['artifacts'] as Map<String, dynamic>)['run_directory'];
      final runPath = '${Directory.current.path}/$runDirectory';
      addTearDown(() async {
        final directory = Directory(runPath);
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final steps = (report['steps'] as List).cast<Map<String, dynamic>>();
      expect(steps, hasLength(2));
      for (final step in steps) {
        final stdoutLog = File(
          '${Directory.current.path}/${step['stdout_log']}',
        );
        final stderrLog = File(
          '${Directory.current.path}/${step['stderr_log']}',
        );
        expect(await stdoutLog.readAsString(), 'fake sdk stdout\n');
        expect(await stderrLog.readAsString(), 'fake sdk stderr\n');
      }
    },
  );

  test(
    'dry-run prints strict JSON with resolved SDK commands and log paths',
    () async {
      const flutterBin = '/tmp/mozais-test-sdk/bin/flutter';
      const dartBin = '/tmp/mozais-test-sdk/bin/dart';
      final result = await _runTool(
        ['verify', '--format', 'json', '--dry-run'],
        environment: {
          'MOZAIS_FLUTTER_BIN': flutterBin,
          'MOZAIS_DART_BIN': dartBin,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr);
      final plan = jsonDecode(result.stdout) as Map<String, dynamic>;
      expect(plan['dry_run'], isTrue);
      expect(
        (plan['artifacts'] as Map<String, dynamic>).containsKey('events'),
        isTrue,
      );
      final steps = (plan['steps'] as List).cast<Map<String, dynamic>>();
      expect(steps, isNotEmpty);
      expect(steps.every((step) => step.containsKey('stdout_log')), isTrue);
      expect(steps.every((step) => step.containsKey('stderr_log')), isTrue);
      expect(
        steps.any(
          (step) =>
              step['command'] is List &&
              (step['command'] as List).first == 'fvm',
        ),
        isFalse,
      );

      final sdkSteps = {
        for (final step in steps)
          if ((step['id'] as String).startsWith('scenes.') ||
              (step['id'] as String).startsWith('scene_schema.') ||
              (step['id'] as String).startsWith('scene_codegen.') ||
              (step['id'] as String).startsWith('scene.') ||
              (step['id'] as String).startsWith('greeter_ui.') ||
              (step['id'] as String).startsWith('flutter.') ||
              (step['id'] as String) == 'dbus.smoke')
            step['id'] as String: (step['command'] as List).cast<String>(),
      };
      expect(
        sdkSteps.entries
                .where(
                  (entry) =>
                      entry.key.startsWith('scenes.') ||
                      entry.key.startsWith('scene_schema.') ||
                      entry.key.startsWith('scene_codegen.'),
                )
                .every((entry) => entry.value.first == dartBin) &&
            sdkSteps['dbus.smoke']![2] == dartBin,
        isTrue,
      );
      expect(
        sdkSteps.entries
            .where(
              (entry) =>
                  entry.key.startsWith('flutter.') ||
                  entry.key.startsWith('scene.') ||
                  entry.key.startsWith('greeter_ui.'),
            )
            .every((entry) => entry.value.first == flutterBin),
        isTrue,
      );
      expect(
        Directory('${Directory.current.path}/${plan['run_directory']}')
            .existsSync(),
        isFalse,
      );

      final derivedDartResult = await _runTool(
        ['generate-scenes', '--dry-run'],
        environment: {'MOZAIS_FLUTTER_BIN': flutterBin},
        unsetEnvironmentVariables: {'MOZAIS_DART_BIN'},
      );
      expect(derivedDartResult.exitCode, 0, reason: derivedDartResult.stderr);
      final derivedDartPlan =
          jsonDecode(derivedDartResult.stdout) as Map<String, dynamic>;
      final firstStep =
          ((derivedDartPlan['steps'] as List).first as Map<String, dynamic>);
      expect(
        (firstStep['command'] as List).first,
        '/tmp/mozais-test-sdk/bin/dart',
      );
    },
  );

  test('performance raw reports use a fresh run directory', () async {
    final firstResult = await _runTool([
      'verify-perf',
      '--format',
      'json',
      '--dry-run',
      '--cycles',
      '3',
    ]);
    final firstPlan = jsonDecode(firstResult.stdout) as Map<String, dynamic>;
    final oldRunPath =
        '${Directory.current.path}/${firstPlan['run_directory']}';
    final oldRunDirectory = Directory(oldRunPath);
    await oldRunDirectory.create(recursive: true);
    addTearDown(() async {
      if (oldRunDirectory.existsSync()) {
        await oldRunDirectory.delete(recursive: true);
      }
    });

    final secondResult = await _runTool([
      'verify-perf',
      '--format',
      'json',
      '--dry-run',
      '--cycles',
      '3',
    ]);
    expect(secondResult.exitCode, 0, reason: secondResult.stderr);
    final secondPlan = jsonDecode(secondResult.stdout) as Map<String, dynamic>;
    expect(secondPlan['run_id'], isNot(firstPlan['run_id']));

    final rawDirectory =
        (secondPlan['artifacts']
            as Map<String, dynamic>)['performance_raw_reports'];
    expect(rawDirectory, startsWith(secondPlan['run_directory']));
    final driveSteps = (secondPlan['steps'] as List)
        .cast<Map<String, dynamic>>()
        .where(
          (step) => (step['id'] as String).startsWith('performance.drive_'),
        );
    expect(driveSteps, hasLength(3));
    for (final step in driveSteps) {
      final command = (step['command'] as List).cast<String>();
      expect(
        command.any((argument) => argument.contains(rawDirectory)),
        isTrue,
      );
    }
  });

  test(
    'failed step stops the plan and still writes report, events, and logs',
    () async {
      final status = await runDevCommand(
        command: 'verify',
        format: RunOutputFormat.json,
        reportPath: null,
        repoRoot: tempRoot,
        runDirectory: 'runs/failure-case',
        steps: [
          RunStep(
            id: 'first.failure',
            command: [
              'bash',
              '-c',
              'printf "first stdout\\n"; printf "first stderr\\n" >&2; exit 23',
            ],
            workingDirectory: '.',
            environment: const {},
          ),
          RunStep(
            id: 'must.not.run',
            command: ['bash', '-c', 'touch should-not-exist'],
            workingDirectory: '.',
            environment: const {},
          ),
        ],
        artifactPaths: const {},
      );

      expect(status, 1);
      expect(File('${tempRoot.path}/should-not-exist').existsSync(), isFalse);
      final reportFile = File('${tempRoot.path}/runs/failure-case/report.json');
      final reportText = await reportFile.readAsString();
      final report = jsonDecode(reportText) as Map<String, dynamic>;
      expect(report['status'], 'failed');
      final steps = (report['steps'] as List).cast<Map<String, dynamic>>();
      expect(steps, hasLength(1));
      expect(steps.single['exit_code'], 23);
      for (final pathKey in ['stdout_log', 'stderr_log']) {
        final path = steps.single[pathKey] as String;
        expect(File('${tempRoot.path}/$path').existsSync(), isTrue);
      }

      final stdoutLog = File('${tempRoot.path}/${steps.single['stdout_log']}');
      final stderrLog = File('${tempRoot.path}/${steps.single['stderr_log']}');
      expect(await stdoutLog.readAsString(), 'first stdout\n');
      expect(await stderrLog.readAsString(), 'first stderr\n');

      final eventsFile = File(
        '${tempRoot.path}/runs/failure-case/events.jsonl',
      );
      final events = (await eventsFile.readAsLines())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(events.first['event'], 'run_started');
      expect(events.last['event'], 'run_finished');
      expect(events.last['status'], 'failed');
      expect(
        events.where((event) => event['event'] == 'step_started'),
        hasLength(1),
      );
      expect(
        events.where((event) => event['event'] == 'step_finished'),
        hasLength(1),
      );
    },
  );

  test(
    'reports and logs redact command, environment, token, and PAM secrets',
    () async {
      const pamSecret = 'pam-secret-value-349';
      const token = 'token-value-832';
      const password = 'password-value-176';
      const apiKey = 'api-key-value-417';
      const commandToken = 'command-token-value-269';
      final status = await runDevCommand(
        command: 'verify',
        format: RunOutputFormat.json,
        reportPath: null,
        repoRoot: tempRoot,
        runDirectory: 'runs/redaction-case',
        steps: [
          RunStep(
            id: 'secret.output',
            command: [
              'bash',
              '-c',
              'printf "PAM secret: %s token=%s password=%s api_key=%s\\n" "\$MOZAIS_PAM_SECRET" "\$MOZAIS_TOKEN" "\$PASSWORD" "\$API_KEY"; printf "Bearer %s\\n" "\$MOZAIS_AUTHORIZATION"',
              '--token',
              commandToken,
            ],
            workingDirectory: '.',
            environment: const {
              'MOZAIS_PAM_SECRET': pamSecret,
              'MOZAIS_TOKEN': token,
              'PASSWORD': password,
              'API_KEY': apiKey,
              'MOZAIS_AUTHORIZATION': 'Bearer authorization-value-551',
            },
          ),
        ],
        artifactPaths: const {},
      );

      expect(status, 0);
      final runDirectory = Directory('${tempRoot.path}/runs/redaction-case');
      final report = await File('${runDirectory.path}/report.json')
          .readAsString();
      final events = await File('${runDirectory.path}/events.jsonl')
          .readAsString();
      final stdoutLog = await File(
        '${runDirectory.path}/secret.output.stdout.log',
      ).readAsString();
      final stderrLog = await File(
        '${runDirectory.path}/secret.output.stderr.log',
      ).readAsString();
      final persisted = '$report\n$events\n$stdoutLog\n$stderrLog';
      for (final secret in [
        pamSecret,
        token,
        password,
        apiKey,
        commandToken,
        'authorization-value-551',
      ]) {
        expect(persisted, isNot(contains(secret)));
      }
      expect(report, contains('[REDACTED]'));
      expect(stdoutLog, contains('[REDACTED]'));
    },
  );
}

Future<Directory> _createThemeProject(Directory parent) async {
  final project = Directory('${parent.path}/external theme');
  await Directory('${project.path}/lib').create(recursive: true);
  await File('${project.path}/pubspec.yaml').writeAsString('''
name: theme_ocean
environment:
  sdk: ^3.13.2
''');
  await File('${project.path}/lib/theme.dart').writeAsString('''
import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

ThemeDefinition buildOceanTheme({Color? seed}) => throw UnimplementedError();
''');
  await File('${project.path}/lib/ocean.scene.json').writeAsString('{}');
  return project;
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

Future<ProcessResult> _runTool(
  List<String> arguments, {
  Map<String, String> environment = const {},
  Set<String> unsetEnvironmentVariables = const {},
}) {
  final dartCommand = getDartCommand(Directory.current);
  final childEnvironment = {...Platform.environment};
  for (final key in unsetEnvironmentVariables) {
    childEnvironment.remove(key);
  }
  childEnvironment.addAll(environment);
  return Process.run(
    dartCommand.first,
    [...dartCommand.skip(1), 'tool/mozais.dart', ...arguments],
    workingDirectory: Directory.current.path,
    environment: childEnvironment,
    includeParentEnvironment: false,
  );
}
