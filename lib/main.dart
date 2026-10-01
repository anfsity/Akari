export 'app/app.dart' show MyApp;

import 'package:flutter/widgets.dart';
import 'package:theme_catalog/theme_catalog.dart';

import 'app/app.dart';
import 'infrastructure/preferences/file_session_store.dart';

void main() {
  const themeName = String.fromEnvironment(
    'MOZAIS_THEME',
    defaultValue: ThemeRegistry.defaultThemeName,
  );
  runApp(
    MyApp(
      themeBuilder: ({seed}) => ThemeRegistry.resolve(themeName, seed: seed),
      sessionStore: FileSessionStore(),
    ),
  );
}
