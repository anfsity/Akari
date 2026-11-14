import 'dart:convert';
import 'dart:io';

import 'package:greeter_ui/greeter_ui.dart';

/// Persists the selected session as a hint for the next login. Greeter accounts
/// may lack writable storage, so missing, corrupt, or inaccessible preferences
/// must never prevent authentication.
class FileSessionStore implements SessionStore {
  FileSessionStore({File? file}) : _file = file ?? _findDefaultFile();

  final File? _file;
  Future<void> _pendingWrite = Future<void>.value();
  static int _nextTempId = 0;

  @override
  Future<String?> findSelectedSessionId() async {
    final file = _file;
    if (file == null) {
      return null;
    }
    try {
      return switch (jsonDecode(await file.readAsString())) {
        {'sessionId': final String id} when id.isNotEmpty => id,
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveSelectedSessionId(String sessionId) {
    final file = _file;
    if (file == null) {
      return Future<void>.value();
    }
    return _pendingWrite = _pendingWrite.then(
      (_) => _writeAtomically(file, sessionId),
    );
  }

  Future<void> _writeAtomically(File target, String sessionId) async {
    File? tempFile;
    try {
      final parent = target.parent;
      if (await FileSystemEntity.isLink(parent.path) ||
          await FileSystemEntity.isLink(target.path)) {
        return;
      }
      await parent.create(recursive: true);
      tempFile = File('${target.path}.$pid.${_nextTempId++}.tmp');
      await tempFile.writeAsString(
        jsonEncode({'sessionId': sessionId}),
        flush: true,
      );
      await tempFile.rename(target.path);
      tempFile = null;
    } on Object {
      // A failed preference write must not interrupt the login flow.
    } finally {
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } on Object {
          // Best-effort temp cleanup.
        }
      }
    }
  }

  static File? _findDefaultFile() {
    final stateHome = Platform.environment['XDG_STATE_HOME'];
    final home = Platform.environment['HOME'];
    final String base;
    if (stateHome != null && stateHome.isNotEmpty) {
      base = stateHome;
    } else if (home != null && home.isNotEmpty) {
      base = '$home/.local/state';
    } else {
      return null;
    }
    return File('$base/akari/greeter.json');
  }
}
