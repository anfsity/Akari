import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'default.scene.g.dart';

/// Seed used before extraction runs and when the wallpaper cannot be sampled.
const _fallbackSeed = Color(0xffb79cff);
ThemeBundle buildDefaultTheme({Color? seed, SceneDocument? document}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seed ?? _fallbackSeed,
    brightness: Brightness.dark,
  );
  final surface = colorScheme.surfaceContainerLow;
  final surfaceVariant = colorScheme.surfaceContainerHighest;
  final text = colorScheme.onSurface;
  return ThemeBundle(
    id: 'default',
    tokens: ThemeTokens(
      materialTheme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: Typography.whiteMountainView.apply(
          bodyColor: text,
          displayColor: text,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          hintStyle: TextStyle(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
            fontSize: 16,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          border: _fieldBorder(Colors.transparent, 0),
          enabledBorder: _fieldBorder(Colors.white.withValues(alpha: 0.06), 1),
          focusedBorder: _fieldBorder(colorScheme.primary, 2),
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
      panelRadius: 28,
      mediumMotion: const Duration(milliseconds: 260),
      standardCurve: Curves.easeOutCubic,
      minHitTarget: 44,
      surfaceColor: surface,
      surfaceVariantColor: surfaceVariant,
    ),
    document: document ?? defaultSceneDocument,
    backgrounds: const {
      SceneBackgroundKind.image: ImageBackgroundRenderer(),
      SceneBackgroundKind.solid: SolidBackgroundRenderer(),
    },
    motions: const {
      SceneMotionPreset.fade: FadeMotionBuilder(),
      SceneMotionPreset.fadeSlide: FadeSlideMotionBuilder(),
      SceneMotionPreset.fadeScale: FadeScaleMotionBuilder(),
      SceneMotionPreset.hoverLift: HoverLiftMotionBuilder(),
      SceneMotionPreset.focusGlow: FocusGlowMotionBuilder(),
    },
  );
}

OutlineInputBorder _fieldBorder(Color color, double width) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color, width: width),
  );
}
