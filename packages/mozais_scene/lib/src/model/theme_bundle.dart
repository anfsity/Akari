import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import '../runtime/background_renderer.dart';
import '../runtime/motion.dart';
import 'theme_tokens.dart';

class ThemeBundle {
  ThemeBundle({
    required this.tokens,
    Map<SceneBackgroundKind, BackgroundRenderer> backgrounds = const {},
    Map<SceneMotionPreset, SceneMotionBuilder> motions = const {},
  }) : backgrounds = Map.unmodifiable(backgrounds),
       motions = Map.unmodifiable(motions);

  final ThemeTokens tokens;
  final Map<SceneBackgroundKind, BackgroundRenderer> backgrounds;
  final Map<SceneMotionPreset, SceneMotionBuilder> motions;

  BackgroundRenderer? backgroundRenderer(SceneBackgroundKind kind) {
    return backgrounds[kind];
  }

  ThemeBundle copyWith({
    ThemeTokens? tokens,
    Map<SceneBackgroundKind, BackgroundRenderer>? backgrounds,
    Map<SceneMotionPreset, SceneMotionBuilder>? motions,
  }) {
    return ThemeBundle(
      tokens: tokens ?? this.tokens,
      backgrounds: backgrounds ?? this.backgrounds,
      motions: motions ?? this.motions,
    );
  }

  SceneMotionBuilder? motionBuilder(SceneMotionPreset preset) {
    return motions[preset];
  }

  ThemeData get materialTheme => tokens.materialTheme;
}
