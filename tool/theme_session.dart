import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'src/sdk_commands.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: dart tool/theme_session.dart THEME HOST MODE demo|real',
    );
    exitCode = 2;
    return;
  }
  final repoRoot = File.fromUri(Platform.script).parent.parent;
  exitCode = await startThemeSession(
    repoRoot: repoRoot,
    theme: Directory(arguments[0]),
    host: Directory(arguments[1]),
    mode: arguments[2],
    backend: arguments[3],
  );
}

/// Owns one Flutter machine session. Source events are debounced and serialized:
/// scene generation must finish successfully before the VM receives a reload.
/// Flutter remains responsible for incremental compilation and application state.
Future<int> startThemeSession({
  required Directory repoRoot,
  required Directory theme,
  required Directory host,
  required String mode,
  required String backend,
}) async {
  final flutter = getFlutterCommand(repoRoot);
  final process = await Process.start(flutter.first, [
    ...flutter.skip(1),
    'run',
    '-d',
    'linux',
    '--$mode',
    '--no-pub',
    '--machine',
    '--dart-define=MOZAIS_BACKEND=$backend',
  ], workingDirectory: host.path);
  final subscriptions = <StreamSubscription<dynamic>>[];
  final watched = <String>{};
  final requests = <int, Completer<Map<String, dynamic>>>{};
  var requestId = 0;
  String? appId;
  var ready = false;
  var stopping = false;
  var reloadPending = false;
  var generationPending = false;
  var restartPending = false;
  var reloading = false;
  Timer? debounce;
  Process? generator;

  Future<Map<String, dynamic>> sendRequest(
    String method,
    Map<String, Object?> params,
  ) {
    final id = ++requestId;
    final response = Completer<Map<String, dynamic>>();
    requests[id] = response;
    process.stdin.writeln(
      jsonEncode([
        {'id': id, 'method': method, 'params': params},
      ]),
    );
    return response.future;
  }

  Future<void> stopSession() async {
    if (stopping) return;
    stopping = true;
    generator?.kill();
    if (appId == null) {
      process.kill();
    } else {
      await sendRequest('app.stop', {'appId': appId});
    }
  }

  Future<void> reloadTheme() async {
    if (!ready || stopping || reloading) return;
    reloading = true;
    try {
      while (reloadPending && !stopping) {
        // Consume this batch before yielding. Saves during generation or reload
        // set the flags again and are handled by the next iteration instead of
        // launching overlapping generators or losing the later source change.
        reloadPending = false;
        final generate = generationPending;
        generationPending = false;
        final restart = restartPending;
        restartPending = false;
        if (generate) {
          final dart = getDartCommand(repoRoot);
          generator = await Process.start(dart.first, [
            ...dart.skip(1),
            'run',
            'build_runner',
            'build',
          ], workingDirectory: theme.path);
          final output = Future.wait([
            generator!.stdout.listen(stdout.add).asFuture<void>(),
            generator!.stderr.listen(stderr.add).asFuture<void>(),
          ]);
          final status = await generator!.exitCode;
          await output;
          generator = null;
          if (status != 0) {
            stderr.writeln(
              'Scene generation failed; keeping the running theme.',
            );
            continue;
          }
        }
        if (stopping) break;
        final response = await sendRequest('app.restart', {
          'appId': appId,
          'fullRestart': restart,
          'pause': false,
          'reason': 'Mozais theme changed',
        });
        if (response.containsKey('error')) {
          stderr.writeln('Flutter reload failed: ${response['error']}');
        } else {
          final result = response['result'] as Map<String, dynamic>;
          stdout.writeln(
            result['message'] ??
                (restart ? 'Hot restart complete.' : 'Hot reload complete.'),
          );
        }
      }
    } finally {
      reloading = false;
    }
  }

  void queueReload({bool generate = false, bool restart = false}) {
    if (mode != 'debug' || stopping) return;
    reloadPending = true;
    // Coalesce with OR: a later Dart-only event must not erase a pending scene
    // regeneration or turn an explicitly requested restart into a hot reload.
    generationPending |= generate;
    restartPending |= restart;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(reloadTheme());
    });
  }

  void watchDirectory(Directory directory) {
    if (!directory.existsSync() || !watched.add(directory.path)) return;
    subscriptions.add(
      directory.watch().listen(
        (event) {
          if (event.isDirectory) {
            if (event.type == FileSystemEvent.create ||
                event.type == FileSystemEvent.move) {
              watchDirectory(Directory(event.path));
            }
            return;
          }
          // build_runner writes these itself; watching its output as a source
          // edit would schedule a second reload for every scene regeneration.
          if (event.path.endsWith('.scene.g.dart')) return;
          final dart = event.path.endsWith('.dart');
          final scene = event.path.endsWith('.scene.json');
          final asset = event.path.contains('/assets/');
          if (dart || scene || asset) {
            queueReload(
              generate: scene || event.path.contains('/scene_codegen/lib/'),
            );
          }
        },
        onError: (Object error) {
          stderr.writeln('Theme source watcher failed: $error');
          unawaited(stopSession());
        },
      ),
    );
    for (final child
        in directory.listSync(followLinks: false).whereType<Directory>()) {
      watchDirectory(child);
    }
  }

  final outputDone = Completer<void>();
  subscriptions.add(
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!line.startsWith('[{') || !line.endsWith('}]')) {
            stdout.writeln(line);
            return;
          }
          final messages = jsonDecode(line) as List;
          for (final value in messages) {
            final message = value as Map<String, dynamic>;
            final id = message['id'];
            if (id is int) {
              requests.remove(id)?.complete(message);
              continue;
            }
            final params = message['params'] as Map<String, dynamic>?;
            switch (message['event']) {
              case 'app.start':
                appId = params!['appId'] as String;
              case 'app.started':
                ready = true;
                stdout.writeln(
                  mode == 'debug'
                      ? 'Greeter ready. Sources reload on save; r reloads, R restarts, q quits.'
                      : 'Greeter ready. Press q to quit.',
                );
                unawaited(reloadTheme());
              case 'app.log':
                stdout.writeln(params!['log']);
              case 'app.progress':
                if (params!['message'] != null) {
                  stdout.writeln(params['message']);
                }
              case 'daemon.logMessage':
                stdout.writeln(params!['message']);
            }
          }
        }, onDone: outputDone.complete),
  );
  final stderrDone = process.stderr.listen(stderr.add).asFuture<void>();
  subscriptions.add(
    stdin.listen((bytes) {
      for (final byte in bytes) {
        switch (byte) {
          case 114:
            queueReload(generate: true);
          case 82:
            queueReload(generate: true, restart: true);
          case 113:
          case 3:
            unawaited(stopSession());
        }
      }
    }),
  );
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    subscriptions.add(
      signal.watch().listen((_) {
        unawaited(stopSession());
      }),
    );
  }
  if (mode == 'debug') {
    watchDirectory(Directory('${theme.path}/lib'));
    watchDirectory(Directory('${theme.path}/assets'));
    watchDirectory(Directory('${repoRoot.path}/lib'));
    for (final package in Directory(
      '${repoRoot.path}/packages',
    ).listSync().whereType<Directory>()) {
      watchDirectory(Directory('${package.path}/lib'));
    }
  }

  try {
    final status = await process.exitCode;
    await Future.wait([outputDone.future, stderrDone]);
    return status;
  } finally {
    stopping = true;
    debounce?.cancel();
    generator?.kill();
    // Closing Flutter must settle requests awaiting machine-protocol replies;
    // otherwise an in-flight reload/stop would wait forever after process exit.
    for (final request in requests.values) {
      request.complete({'error': 'Flutter session closed.'});
    }
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}
