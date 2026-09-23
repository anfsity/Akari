import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'nocturne.scene.g.dart';

/// A low-cost 2.5D login composition. Depth comes from layered surfaces and
/// directional shadows instead of a live blur, so the greeter stays responsive
/// on integrated GPUs.
const _ink = Color(0xff07111f);
const _panel = Color(0xff101b31);
const _panelRaised = Color(0xff182844);
const _cyan = Color(0xff66e7ff);
const _gold = Color(0xffffc56e);
const _text = Color(0xfff0f7ff);

ThemeBundle buildNocturneTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: _cyan,
        brightness: Brightness.dark,
      ).copyWith(
        primary: _gold,
        onPrimary: _ink,
        secondary: _cyan,
        onSecondary: _ink,
        surface: _ink,
        onSurface: _text,
        surfaceContainerHighest: _panelRaised,
      );
  return ThemeBundle(
    id: 'nocturne',
    tokens: ThemeTokens(
      materialTheme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: Typography.whiteMountainView.apply(
          bodyColor: _text,
          displayColor: _text,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _panel,
          hintStyle: TextStyle(
            color: _text.withValues(alpha: 0.48),
            fontSize: 16,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          border: _border(_panelRaised, 1),
          enabledBorder: _border(_panelRaised, 1),
          focusedBorder: _border(_gold, 2),
          disabledBorder: _border(_panelRaised.withValues(alpha: 0.55), 1),
          isDense: true,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: _ink,
            minimumSize: const Size(44, 44),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: _cyan,
            minimumSize: const Size(44, 44),
          ),
        ),
      ),
      panelRadius: 26,
      mediumMotion: const Duration(milliseconds: 220),
      standardCurve: Curves.easeOutCubic,
      minHitTarget: 44,
      allowBlur: false,
      blurSigma: 0,
      glassColor: _panel.withValues(alpha: 0.96),
      surfaceColor: _panel,
      surfaceVariantColor: _panelRaised,
    ),
    document: nocturneSceneDocument,
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

OutlineInputBorder _border(Color color, double width) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color, width: width),
  );
}
