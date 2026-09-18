import 'package:mozais_scene/mozais_scene.dart';

import '../themes/default/theme.dart';
import '../themes/fallback/theme.dart';

class ThemeRegistry {
  const ThemeRegistry._();

  static const defaultThemeName = 'default';
  static const fallbackThemeName = 'fallback';

  static ThemeBundle resolve(String name) {
    assert(
      name == defaultThemeName || name == fallbackThemeName,
      'Unknown MOZAIS_THEME "$name"; falling back to $fallbackThemeName.',
    );
    return switch (name) {
      defaultThemeName => buildDefaultTheme(),
      fallbackThemeName => buildFallbackTheme(),
      _ => buildFallbackTheme(),
    };
  }
}
