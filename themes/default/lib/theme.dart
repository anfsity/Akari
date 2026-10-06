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
  final surface = const Color(0xff102e43);
  final surfaceVariant = colorScheme.surfaceContainerHighest;
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
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
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
        filled: true,
        fillColor: surface.withValues(alpha: 0.86),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
          fontSize: 16,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
        border: _fieldBorder(Colors.transparent, 0),
        enabledBorder: _fieldBorder(Colors.white.withValues(alpha: 0.22), 1),
        focusedBorder: _fieldBorder(colorScheme.primary, 1.5),
        disabledBorder: _fieldBorder(
          colorScheme.outline.withValues(alpha: 0.24),
          1,
        ),
        isDense: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(44, 44),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurfaceVariant,
          minimumSize: const Size(44, 44),
        ),
      ),
      visualDensity: VisualDensity.standard,
    ),
    panelRadius: 4,
    mediumMotion: const Duration(milliseconds: 480),
    standardCurve: Curves.easeInOutCubic,
    minHitTarget: 44,
    surfaceColor: surface,
    surfaceVariantColor: surfaceVariant,
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
        SceneMotionPreset.fade: FadeMotionBuilder(),
        SceneMotionPreset.fadeSlide: TerraceEntranceMotion(),
        SceneMotionPreset.fadeScale: TerraceEntranceMotion(),
        SceneMotionPreset.hoverLift: TerraceActionMotion(),
        SceneMotionPreset.focusGlow: FocusGlowMotionBuilder(),
      },
    ),
    components: TerraceComponents.new,
  );
}

OutlineInputBorder _fieldBorder(Color color, double width) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: BorderSide(color: color, width: width),
  );
}
