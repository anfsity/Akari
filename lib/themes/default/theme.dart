import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'default.scene.g.dart';

ThemeBundle buildDefaultTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xffd2a35f),
    brightness: Brightness.dark,
  );
  return ThemeBundle(
    id: 'default',
    tokens: ThemeTokens(
      materialTheme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.transparent,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.22),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.32)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.32)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: colorScheme.primary),
          ),
          isDense: true,
        ),
        visualDensity: VisualDensity.standard,
      ),
      pagePadding: const EdgeInsets.all(24),
      panelPadding: const EdgeInsets.all(28),
      contentMaxWidth: 460,
      controlHeight: 52,
      panelRadius: 28,
      sectionGap: 20,
      controlGap: 12,
      shortMotion: const Duration(milliseconds: 140),
      mediumMotion: const Duration(milliseconds: 260),
      standardCurve: Curves.easeOutCubic,
      minHitTarget: 44,
      maxInteractiveRotationDegrees: 15,
      minTextScale: 0.9,
      allowBlur: true,
      blurSigma: 18,
      glassColor: const Color(0x99101317),
      scrimColor: const Color(0x55050a0d),
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
