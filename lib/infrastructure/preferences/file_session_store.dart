import 'dart:convert';
import 'dart:io';

import 'package:greeter_ui/greeter_ui.dart';

/// Persists the selected session as a hint for the next login. Greeter accounts
/// may lack writable storage, so missing, corrupt, or inaccessible preferences
/// must never prevent authentication.
class FileSessionStore implements SessionStore {
  FileSessionStore({File? file}) : _file = file ?? _getDefaultFile();

  final File _file;

  @override
  Future<String?> readSelectedSessionId() async {
    try {
      return switch (jsonDecode(await _file.readAsString())) {
        {'sessionId': final String id} when id.isNotEmpty => id,
        _ => null,
      };
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
      // A failed preference write must not interrupt the login flow.
    }
  }

  static File _getDefaultFile() {
    final stateHome = Platform.environment['XDG_STATE_HOME'];
    final home = Platform.environment['HOME'];
    final String base;
    if (stateHome != null && stateHome.isNotEmpty) {
      base = stateHome;
    } else if (home != null && home.isNotEmpty) {
      base = '$home/.local/state';
    } else {
      base = Directory.systemTemp.path;
    }
    return File('$base/akari/greeter.json');
  }
}
