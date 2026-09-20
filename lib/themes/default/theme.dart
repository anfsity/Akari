import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'default.scene.g.dart';

/// Seed used before extraction runs and whenever the wallpaper cannot be
/// sampled. It was sampled from the bundled wallpaper's dominant vibrant hue.
const _fallbackSeed = Color(0xfff26d7a);
const _base = Color(0xff1a1c18);
const _surface = Color(0xff2a2d28);
const _surfaceVariant = Color(0xff3a3e36);
const _text = Color(0xffe3e3dc);

ThemeBundle buildDefaultTheme({Color? seed}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seed ?? _fallbackSeed,
    brightness: Brightness.dark,
  ).copyWith(surface: _base, onSurface: _text);
  return ThemeBundle(
    id: 'default',
    tokens: ThemeTokens(
      materialTheme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.transparent,
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
          isDense: true,
        ),
        visualDensity: VisualDensity.standard,
      ),
      panelRadius: 32,
      mediumMotion: const Duration(milliseconds: 260),
      standardCurve: Curves.easeOutCubic,
      minHitTarget: 44,
      maxInteractiveRotationDegrees: 15,
      allowBlur: false,
      blurSigma: 0,
      glassColor: _base.withValues(alpha: 0.72),
      surfaceColor: _surface,
      surfaceVariantColor: _surfaceVariant,
    ),
    document: defaultSceneDocument,
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
