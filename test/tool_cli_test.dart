import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/run_report.dart';

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

Future<ProcessResult> _runTool(
  List<String> arguments, {
  Map<String, String> environment = const {},
  Set<String> unsetEnvironmentVariables = const {},
}) {
  final dartBin =
      Platform.environment['MOZAIS_DART_BIN'] ?? Platform.resolvedExecutable;
  final childEnvironment = {...Platform.environment};
  for (final key in unsetEnvironmentVariables) {
    childEnvironment.remove(key);
  }
  childEnvironment.addAll(environment);
  return Process.run(
    dartBin,
    ['tool/mozais.dart', ...arguments],
    workingDirectory: Directory.current.path,
    environment: childEnvironment,
    includeParentEnvironment: false,
  );
}
