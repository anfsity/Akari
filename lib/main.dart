export 'app/app.dart' show MyApp;

import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'infrastructure/preferences/file_session_store.dart';

void main() {
  runApp(MyApp(sessionStore: FileSessionStore()));
}
