import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import '../runtime/background_renderer.dart';
import '../runtime/motion.dart';
import 'theme_tokens.dart';

class ThemeBundle {
  ThemeBundle({
    required this.id,
    required this.tokens,
    required this.document,
    Map<SceneBackgroundKind, BackgroundRenderer> backgrounds = const {},
    Map<SceneMotionPreset, SceneMotionBuilder> motions = const {},
  }) : backgrounds = Map.unmodifiable(backgrounds),
       motions = Map.unmodifiable(motions);

  final String id;
  final ThemeTokens tokens;
  final SceneDocument document;
  final Map<SceneBackgroundKind, BackgroundRenderer> backgrounds;
  final Map<SceneMotionPreset, SceneMotionBuilder> motions;

  BackgroundRenderer? backgroundRenderer(SceneBackgroundKind kind) {
    return backgrounds[kind];
  }

  ThemeBundle copyWith({
    String? id,
    ThemeTokens? tokens,
    SceneDocument? document,
    Map<SceneBackgroundKind, BackgroundRenderer>? backgrounds,
    Map<SceneMotionPreset, SceneMotionBuilder>? motions,
  }) {
    return ThemeBundle(
      id: id ?? this.id,
      tokens: tokens ?? this.tokens,
      document: document ?? this.document,
      backgrounds: backgrounds ?? this.backgrounds,
      motions: motions ?? this.motions,
    );
  }

  SceneMotionBuilder? motionBuilder(SceneMotionPreset preset) {
    return motions[preset];
  }

  ThemeData get materialTheme => tokens.materialTheme;
}
