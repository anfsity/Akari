import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/sdk_commands.dart';

void main() {
  test(
    'D-Bus launcher reuses prepared backend, forwards input, and cleans it up',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'akari-dbus-session-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final backend = File('${temporary.path}/backend');
      final busctl = File('${temporary.path}/busctl');
      final client = File('${temporary.path}/client');
      final stopped = File('${temporary.path}/stopped');
      final received = File('${temporary.path}/received');
      await backend.writeAsString('''#!/bin/bash
trap 'printf stopped > "${stopped.path}"; exit 0' TERM
while true; do sleep 0.05; done
''');
      await busctl.writeAsString('#!/bin/sh\nexit 0\n');
      await client.writeAsString('''#!/bin/bash
read -r value
printf '%s' "\$value" > "${received.path}"
exit 17
''');
      final chmod = await Process.run('chmod', [
        '+x',
        backend.path,
        busctl.path,
        client.path,
      ]);
      expect(chmod.exitCode, 0);
      final launcher = await Process.start(
        'bash',
        ['scripts/debug-dbus.sh', '--inside-private-bus', client.path],
        environment: {
          'PATH': '${temporary.path}:${Platform.environment['PATH']}',
          'AKARI_PRIVATE_BUS': '1',
          'AKARI_BACKEND_BIN': backend.path,
          'AKARI_LOG_DIR': '${temporary.path}/logs',
        },
      );
      launcher.stdin.writeln('input');
      await launcher.stdin.close();
      final output = Future.wait([
        launcher.stdout.drain<void>(),
        launcher.stderr.drain<void>(),
      ]);
      expect(await launcher.exitCode.timeout(const Duration(seconds: 10)), 17);
      await output;
      expect(await received.readAsString(), 'input');
      expect(await stopped.readAsString(), 'stopped');
    },
  );

  test(
    'scene generation precedes reload and failures preserve the running app',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'akari-session-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final theme = Directory('${temporary.path}/theme');
      await Directory('${theme.path}/lib').create(recursive: true);
      final scene = File('${theme.path}/lib/test.scene.json');
      await scene.writeAsString('initial');
      final generated = File('${temporary.path}/generated');
      final flutter = File('${temporary.path}/flutter');
      await flutter.writeAsString('''#!/usr/bin/env python3
import json, pathlib, sys
assert '--no-pub' in sys.argv
print(json.dumps([{'event':'app.start', 'params':{'appId':'test'}}]), flush=True)
print(json.dumps([{'event':'app.started', 'params':{'appId':'test'}}]), flush=True)
for line in sys.stdin:
    request = json.loads(line)[0]
    if request['method'] == 'app.restart':
        assert pathlib.Path(${jsonEncode(generated.path)}).read_text() == 'updated'
        result = {'code':0, 'message':'reloaded'}
    else:
        result = True
    print(json.dumps([{'id':request['id'], 'result':result}]), flush=True)
    if request['method'] == 'app.stop':
        sys.exit(0)
''');
      final dart = File('${temporary.path}/dart');
      await dart.writeAsString('''#!/usr/bin/env python3
import pathlib, sys
content = pathlib.Path(${jsonEncode(scene.path)}).read_text()
if content == 'invalid':
    sys.exit(7)
pathlib.Path(${jsonEncode(generated.path)}).write_text(content)
''');
      final chmod = await Process.run('chmod', ['+x', flutter.path, dart.path]);
      expect(chmod.exitCode, 0);
      final sdk = getDartCommand(Directory.current);
      final process = await Process.start(
        sdk.first,
        [
          ...sdk.skip(1),
          'tool/theme_session.dart',
          theme.path,
          temporary.path,
          'debug',
          'demo',
        ],
        environment: {
          'AKARI_FLUTTER_BIN': flutter.path,
          'AKARI_DART_BIN': dart.path,
        },
      );
      addTearDown(() {
        process.kill();
      });
      final ready = Completer<void>();
      final failed = Completer<void>();
      final reloaded = Completer<void>();
      final output = <String>[];
      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            output.add(line);
            if (line.startsWith('Greeter ready')) ready.complete();
            if (line == 'reloaded') reloaded.complete();
          })
          .asFuture<void>();
      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            output.add(line);
            if (line.startsWith('Scene generation failed')) failed.complete();
          })
          .asFuture<void>();
      await ready.future.timeout(const Duration(seconds: 15));
      await scene.writeAsString('invalid');
      await failed.future.timeout(const Duration(seconds: 15));
      expect(output, isNot(contains('reloaded')));
      final saved = await scene.parent.createTemp('.akari-studio-');
      await File('${saved.path}/scene.json').writeAsString('updated');
      await File('${saved.path}/scene.json').rename(scene.path);
      await saved.delete();
      await reloaded.future.timeout(const Duration(seconds: 15));
      process.stdin.write('q');
      expect(await process.exitCode.timeout(const Duration(seconds: 15)), 0);
      await Future.wait([stdoutDone, stderrDone]);
      expect(await generated.readAsString(), 'updated');
    },
  );
}
