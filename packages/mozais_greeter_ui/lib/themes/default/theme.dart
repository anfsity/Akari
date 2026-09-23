import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'default.scene.g.dart';

/// Seed used before extraction runs and whenever the wallpaper cannot be
/// sampled. The indigo and coral pairing keeps the login controls legible
/// over both the dark and warm parts of the bundled illustration.
const _fallbackSeed = Color(0xffb79cff);
const _base = Color(0xff10111d);
const _surface = Color(0xff1b1d2d);
const _surfaceVariant = Color(0xff30334b);
const _text = Color(0xfff2f1fb);

ThemeBundle buildDefaultTheme({Color? seed, SceneDocument? document}) {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: seed ?? _fallbackSeed,
        brightness: Brightness.dark,
      ).copyWith(
        secondary: const Color(0xffffb59f),
        onSecondary: _base,
        surface: _base,
        onSurface: _text,
        surfaceContainerHighest: _surfaceVariant,
      );
  return ThemeBundle(
    id: 'default',
    tokens: ThemeTokens(
      materialTheme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: Typography.whiteMountainView.apply(
          bodyColor: _text,
          displayColor: _text,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surface,
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.42),
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
      allowBlur: false,
      blurSigma: 0,
      glassColor: _base.withValues(alpha: 0.82),
      surfaceColor: _surface,
      surfaceVariantColor: _surfaceVariant,
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
