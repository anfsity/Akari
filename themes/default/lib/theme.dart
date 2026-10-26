import 'package:flutter/material.dart';
import 'package:scene/scene.dart';
import 'package:theme_sdk/theme_sdk.dart' show ThemeDefinition;

import 'default.scene.g.dart';
import 'terrace_components.dart';
import 'terrace_visuals.dart';

/// Seed used before extraction runs and when the wallpaper cannot be sampled.
const _fallbackSeed = Color(0xff83cddd);
const _fontFamily = 'packages/theme_default/SpaceGrotesk';
ThemeDefinition buildDefaultTheme({Color? seed, SceneDocument? document}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seed ?? _fallbackSeed,
    brightness: Brightness.dark,
  );
  final surface = const Color(0xff25465e);
  final text = colorScheme.onSurface;
  final tokens = ThemeTokens(
    materialTheme: ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: _fontFamily,
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.2)),
        ),
        textStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 14,
          color: text,
        ),
      ),
      textTheme: Typography.whiteMountainView.apply(
        fontFamily: _fontFamily,
        bodyColor: text,
        displayColor: text,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        fillColor: Colors.transparent,
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
          fontSize: 16,
        ),
        contentPadding: EdgeInsets.zero,
        border: _getFieldBorder(Colors.white.withValues(alpha: 0.3), 1),
        enabledBorder: _getFieldBorder(Colors.white.withValues(alpha: 0.3), 1),
        focusedBorder: _getFieldBorder(colorScheme.primary, 1.5),
        disabledBorder: _getFieldBorder(
          colorScheme.outline.withValues(alpha: 0.3),
          1,
        ),
        isDense: true,
      ),
      visualDensity: VisualDensity.standard,
    ),
    panelRadius: 20,
    mediumMotion: const Duration(milliseconds: 420),
    standardCurve: Curves.linear,
    minHitTarget: 44,
    surfaceColor: surface,
    surfaceVariantColor: colorScheme.surfaceContainerHighest,
  );
  return ThemeDefinition(
    id: 'default',
    document: document ?? defaultSceneDocument,
    bundle: ThemeBundle(
      tokens: tokens,
      backgrounds: const {
        SceneBackgroundKind.image: TerraceBackgroundRenderer(),
        SceneBackgroundKind.solid: SolidBackgroundRenderer(),
      },
      motions: const {
        SceneMotionPreset.fade: TerraceFadeMotion(),
        SceneMotionPreset.fadeSlide: TerraceEntranceMotion(),
        SceneMotionPreset.hoverLift: TerraceActionMotion(),
        SceneMotionPreset.focusGlow: FocusGlowMotionBuilder(),
      },
    ),
    components: TerraceComponents.new,
  );
}

UnderlineInputBorder _getFieldBorder(Color color, double width) {
  return UnderlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: color, width: width),
  );
}
