import 'package:flutter/material.dart';

import '../runtime/background_renderer.dart';
import '../runtime/motion.dart';
import 'scene_document.dart';
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

  SceneMotionBuilder? motionBuilder(SceneMotionPreset preset) {
    return motions[preset];
  }

  ThemeData get materialTheme => tokens.materialTheme;
}
