import 'package:flutter/widgets.dart';
import 'package:greeter/app/app.dart';
import 'package:greeter/infrastructure/preferences/file_session_store.dart';
import 'package:theme_default/theme.dart';

void main() {
  runApp(
    MyApp(themeBuilder: buildDefaultTheme, sessionStore: FileSessionStore()),
  );
}
