import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../sdk_commands.dart';
import 'model.dart';

// A restart includes generation; regeneration includes a reload. Coalescing
// retains the strongest pending request while one serialized batch is active.
enum _ReloadRequest { reload, regenerate, restart }

/// Owns one Flutter machine session and its watchers, protocol requests and
/// generator. A failed generation leaves the current application running;
/// source edits arriving during a batch belong to the next batch.
class ThemeSession {
  ThemeSession({
    required this.repoRoot,
    required this.theme,
    required this.host,
    required this.mode,
    required this.backend,
  });

  final Directory repoRoot;
  final Directory theme;
  final Directory host;
  final BuildMode mode;
  final String backend;

  late final Process _process;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _watched = <String>{};
  final _requests = <int, Completer<Map<String, dynamic>>>{};
  var _requestId = 0;
  String? _appId;
  var _ready = false;
  var _stopping = false;
  var _reloading = false;
  _ReloadRequest? _pendingReload;
  final _pendingGenerationThemes = <String>{};
  bool _generateAllThemes = false;
  Timer? _debounce;
  Process? _generator;
  late final List<Directory> _themes;

  Future<int> start() async {
    final directories = Platform.environment['AKARI_THEME_DIRECTORIES_JSON'];
    _themes = directories == null
        ? [theme]
        : (jsonDecode(directories) as List)
              .cast<String>()
              .map(Directory.new)
              .toList();
    final flutter = getFlutterCommand(repoRoot);
    final previewApplication =
        Platform.environment['AKARI_PREVIEW_APPLICATION'];
    if (previewApplication != null) {
      final interrupted = await _showSplash(
        Platform.environment['AKARI_SPLASH_BIN']!,
      );
      if (interrupted != null) return interrupted;
    }
    _process = await Process.start(flutter.first, [
      ...flutter.skip(1),
      'run',
      '-d',
      'linux',
      '--${mode.name}',
      '--no-pub',
      '--machine',
      '--dart-define=AKARI_BACKEND=$backend',
      if (previewApplication != null)
        '--use-application-binary=$previewApplication',
    ], workingDirectory: host.path);
    final outputDone = Completer<void>();
    _subscriptions.add(
      _process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleFlutterOutput, onDone: outputDone.complete),
    );
    final stderrDone = _process.stderr.listen(stderr.add).asFuture<void>();
    _subscriptions.add(stdin.listen(_handleInput));
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      _subscriptions.add(
        signal.watch().listen((_) {
          unawaited(_stop());
        }),
      );
    }
    if (mode == BuildMode.debug) {
      for (final project in _themes) {
        _watchDirectory(Directory('${project.path}/lib'), sceneTheme: project);
        _watchDirectory(Directory('${project.path}/assets'));
      }
      _watchDirectory(Directory('${repoRoot.path}/lib'));
      for (final package in Directory(
        '${repoRoot.path}/packages',
      ).listSync().whereType<Directory>()) {
        _watchDirectory(Directory('${package.path}/lib'));
      }
    }
    try {
      final status = await _process.exitCode;
      await Future.wait([outputDone.future, stderrDone]);
      return status;
    } finally {
      await _close();
    }
  }

  void _handleInput(List<int> bytes) {
    for (final byte in bytes) {
      switch (byte) {
        case 114:
          _queueReload(_ReloadRequest.regenerate);
        case 82:
          _queueReload(_ReloadRequest.restart);
        case 113:
        case 3:
          unawaited(_stop());
      }
    }
  }

  void _queueReload(_ReloadRequest request, {Directory? sceneTheme}) {
    if (mode != BuildMode.debug || _stopping) return;
    if (request != _ReloadRequest.reload) {
      if (sceneTheme == null) {
        _generateAllThemes = true;
      } else {
        _pendingGenerationThemes.add(sceneTheme.path);
      }
    }
    _pendingReload = switch ((_pendingReload, request)) {
      (_ReloadRequest.restart, _) ||
      (_, _ReloadRequest.restart) => _ReloadRequest.restart,
      (_ReloadRequest.regenerate, _) ||
      (_, _ReloadRequest.regenerate) => _ReloadRequest.regenerate,
      _ => _ReloadRequest.reload,
    };
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    if (!_ready || _stopping || _reloading) return;
    _reloading = true;
    try {
      while (_pendingReload != null && !_stopping) {
        final request = _pendingReload!;
        _pendingReload = null;
        final generationThemes = _generateAllThemes
            ? _themes
            : _themes
                  .where(
                    (project) =>
                        _pendingGenerationThemes.contains(project.path),
                  )
                  .toList();
        _generateAllThemes = false;
        _pendingGenerationThemes.clear();
        if (request != _ReloadRequest.reload &&
            !await _generateScenes(generationThemes)) {
          continue;
        }
        if (_stopping) break;
        final restart = request == _ReloadRequest.restart;
        final response = await _sendRequest('app.restart', {
          'appId': _appId,
          'fullRestart': restart,
          'pause': false,
          'reason': 'Akari theme changed',
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
      _reloading = false;
    }
  }

  Future<bool> _generateScenes(List<Directory> themes) async {
    final dart = getDartCommand(repoRoot);
    for (final project in themes) {
      if (_stopping) return false;
      final generator = await Process.start(dart.first, [
        ...dart.skip(1),
        'run',
        'build_runner',
        'build',
      ], workingDirectory: project.path);
      _generator = generator;
      try {
        final output = Future.wait([
          generator.stdout.listen(stdout.add).asFuture<void>(),
          generator.stderr.listen(stderr.add).asFuture<void>(),
        ]);
        final status = await generator.exitCode;
        await output;
        if (status != 0) {
          stderr.writeln('Scene generation failed; keeping the running theme.');
          return false;
        }
      } finally {
        _generator = null;
      }
    }
    return true;
  }

  Future<Map<String, dynamic>> _sendRequest(
    String method,
    Map<String, Object?> params,
  ) {
    final id = ++_requestId;
    final response = Completer<Map<String, dynamic>>();
    _requests[id] = response;
    _process.stdin.writeln(
      jsonEncode([
        {'id': id, 'method': method, 'params': params},
      ]),
    );
    return response.future;
  }

  Future<void> _stop() async {
    if (_stopping) return;
    _stopping = true;
    _generator?.kill();
    if (_appId == null) {
      _process.kill();
    } else {
      await _sendRequest('app.stop', {'appId': _appId});
    }
  }

  void _watchDirectory(Directory directory, {Directory? sceneTheme}) {
    if (!directory.existsSync() || !_watched.add(directory.path)) return;
    _subscriptions.add(
      directory.watch().listen(
        (event) {
          if (event.isDirectory) {
            if (event.type == FileSystemEvent.create ||
                event.type == FileSystemEvent.move) {
              _watchDirectory(Directory(event.path), sceneTheme: sceneTheme);
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
            _queueReload(
              scene || event.path.contains('/scene_codegen/lib/')
                  ? _ReloadRequest.regenerate
                  : _ReloadRequest.reload,
              sceneTheme: scene ? sceneTheme : null,
            );
          }
        },
        onError: (Object error) {
          stderr.writeln('Theme source watcher failed: $error');
          unawaited(_stop());
        },
      ),
    );
    for (final child
        in directory.listSync(followLinks: false).whereType<Directory>()) {
      _watchDirectory(child, sceneTheme: sceneTheme);
    }
  }

  void _handleFlutterOutput(String line) {
    if (!line.startsWith('[{') || !line.endsWith('}]')) {
      stdout.writeln(line);
      return;
    }
    final messages = jsonDecode(line) as List;
    for (final value in messages) {
      final message = value as Map<String, dynamic>;
      final id = message['id'];
      if (id is int) {
        _requests.remove(id)?.complete(message);
        continue;
      }
      final params = message['params'] as Map<String, dynamic>?;
      switch (message['event']) {
        case 'app.start':
          _appId = params!['appId'] as String;
        case 'app.started':
          _ready = true;
          stdout.writeln(
            mode == BuildMode.debug
                ? 'Greeter ready. Sources reload on save; r reloads, R restarts, q quits.'
                : 'Greeter ready. Press q to quit.',
          );
          unawaited(_reload());
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
  }

  Future<void> _close() async {
    _stopping = true;
    _debounce?.cancel();
    _generator?.kill();
    // Settle requests before cancelling protocol delivery. An in-flight reload
    // or stop must not await a reply from a process that has already exited.
    for (final request in _requests.values) {
      request.complete({'error': 'Flutter session closed.'});
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}

/// The splash is a completed, separate process before Flutter is launched.
/// A window close skips the hold; a terminal signal cancels the whole preview.
Future<int?> _showSplash(String executable) async {
  try {
    final process = await Process.start(
      executable,
      ['window'],
      environment: {'AKARI_SPLASH_PARENT_PID': '$pid'},
    );
    int? interrupted;
    final signals = [
      for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm])
        signal.watch().listen((_) {
          interrupted = signal == ProcessSignal.sigint ? 130 : 143;
          process.kill(signal);
        }),
    ];
    try {
      final output = Future.wait([
        process.stdout.listen(stdout.add).asFuture<void>(),
        process.stderr.listen(stderr.add).asFuture<void>(),
      ]);
      final status = await process.exitCode;
      await output;
      if (status != 0 && interrupted == null) {
        stderr.writeln(
          'Native splash exited with $status; continuing preview.',
        );
      }
      return interrupted;
    } finally {
      for (final signal in signals) {
        await signal.cancel();
      }
    }
  } on ProcessException catch (error) {
    stderr.writeln('Native splash unavailable; continuing preview: $error');
    return null;
  }
}
