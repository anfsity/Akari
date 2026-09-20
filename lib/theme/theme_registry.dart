import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import '../themes/default/theme.dart';
import '../themes/fallback/theme.dart';
import 'palette_extractor.dart';

class ThemeRegistry {
  const ThemeRegistry._();

  static const defaultThemeName = 'default';
  static const fallbackThemeName = 'fallback';

  static ThemeBundle resolve(String name, {Color? accent}) {
    assert(
      name == defaultThemeName || name == fallbackThemeName,
      'Unknown MOZAIS_THEME "$name"; falling back to $fallbackThemeName.',
    );
    return switch (name) {
      defaultThemeName => buildDefaultTheme(accent: accent),
      fallbackThemeName => buildFallbackTheme(),
      _ => buildFallbackTheme(),
    };
  }

  /// Samples the theme background for a dynamic accent.
  ///
  /// Returns null when the theme has no image background or the asset cannot
  /// be decoded, in which case the caller keeps the built-in accent.
  static Future<Color?> findBackgroundAccent(ThemeBundle theme) async {
    final asset = theme.document.background.asset;
    if (asset == null) {
      return null;
    }
    try {
      return await extractAccent(asset);
    } on Object {
      return null;
    }
  }
}
