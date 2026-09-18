import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'fallback.scene.g.dart';

ThemeBundle buildFallbackTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff8fb8c0),
    brightness: Brightness.dark,
  );
  return ThemeBundle(
    id: 'fallback',
    tokens: ThemeTokens(
      materialTheme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xff0d151a),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        visualDensity: VisualDensity.standard,
      ),
      pagePadding: const EdgeInsets.all(24),
      panelPadding: const EdgeInsets.all(28),
      contentMaxWidth: 460,
      controlHeight: 52,
      panelRadius: 12,
      sectionGap: 20,
      controlGap: 12,
      shortMotion: Duration.zero,
      mediumMotion: Duration.zero,
      standardCurve: Curves.linear,
      minHitTarget: 44,
      maxInteractiveRotationDegrees: 0,
      minTextScale: 0.9,
      allowBlur: false,
      blurSigma: 0,
      glassColor: const Color(0xdd11191e),
      scrimColor: const Color(0x00000000),
    ),
    document: fallbackSceneDocument,
    backgrounds: const {
      SceneBackgroundKind.image: ImageBackgroundRenderer(),
      SceneBackgroundKind.solid: SolidBackgroundRenderer(),
    },
    motions: const {SceneMotionPreset.none: FadeMotionBuilder()},
  );
}
