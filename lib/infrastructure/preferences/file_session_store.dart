import 'dart:convert';
import 'dart:io';

import '../../feature/greeter/ports/session_store.dart';

/// Persists the selected session id under the XDG state directory.
///
/// The greeter may run as a system account without a writable home, so every
/// failure degrades to "no stored preference" instead of blocking login.
class FileSessionStore implements SessionStore {
  FileSessionStore({File? file}) : _file = file ?? _defaultFile();

  final File _file;

  @override
  Future<String?> readSelectedSessionId() async {
    try {
      if (!await _file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final id = decoded['sessionId'];
      return id is String && id.isNotEmpty ? id : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveSelectedSessionId(String sessionId) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode({'sessionId': sessionId}));
    } on Object {
      // Best effort: a missing cache never blocks the greeter.
    }
  }

  static File _defaultFile() {
    final environment = Platform.environment;
    final stateHome = environment['XDG_STATE_HOME'];
    final home = environment['HOME'];
    final base = stateHome != null && stateHome.isNotEmpty
        ? stateHome
        : home != null && home.isNotEmpty
        ? '$home/.local/state'
        : Directory.systemTemp.path;
    return File('$base/mozais/greeter.json');
  }
}
