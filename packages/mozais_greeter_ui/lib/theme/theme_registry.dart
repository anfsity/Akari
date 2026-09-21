import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import '../themes/default/theme.dart';
import '../themes/fallback/theme.dart';
import 'palette_extractor.dart';

class ThemeRegistry {
  const ThemeRegistry._();

  static const defaultThemeName = 'default';
  static const fallbackThemeName = 'fallback';

  static ThemeBundle resolve(String name, {Color? seed}) {
    assert(
      name == defaultThemeName || name == fallbackThemeName,
      'Unknown MOZAIS_THEME "$name"; falling back to $fallbackThemeName.',
    );
    return switch (name) {
      defaultThemeName => buildDefaultTheme(seed: seed),
      fallbackThemeName => buildFallbackTheme(),
      _ => buildFallbackTheme(),
    };
  }

  /// Samples the theme background for a dynamic palette seed.
  ///
  /// Returns null when the theme has no image background or the asset cannot
  /// be decoded, in which case the caller keeps the built-in seed.
  static Future<Color?> findBackgroundSeed(ThemeBundle theme) async {
    final asset = theme.document.background.asset;
    if (asset == null) {
      return null;
    }
    try {
      return await extractSeed(asset);
    } on Object {
      return null;
    }
  }
}
