import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';
import 'package:mozais_greeter_components/mozais_greeter_components.dart';
import 'package:mozais_theme_sdk/mozais_theme_sdk.dart' show ThemeDefinition;

import 'fallback.scene.g.dart';

const _accent = Color(0xff8fb8c0);
const _base = Color(0xff0d151a);
const _surface = Color(0xff1a242a);
const _surfaceVariant = Color(0xff26343c);

ThemeDefinition buildFallbackTheme({Color? seed}) {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: _accent,
        onPrimary: _base,
        surface: _base,
        surfaceContainerHigh: _surface,
        surfaceContainerHighest: _surfaceVariant,
      );
  final tokens = ThemeTokens(
    materialTheme: ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _base,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        border: const OutlineInputBorder(),
        enabledBorder: const OutlineInputBorder(),
        isDense: true,
      ),
      visualDensity: VisualDensity.standard,
    ),
    panelRadius: 12,
    mediumMotion: Duration.zero,
    standardCurve: Curves.linear,
    minHitTarget: 44,
    surfaceColor: _surface,
    surfaceVariantColor: _surfaceVariant,
  );
  return ThemeDefinition(
    id: 'fallback',
    document: fallbackSceneDocument,
    bundle: ThemeBundle(
      tokens: tokens,
      backgrounds: const {
        SceneBackgroundKind.image: ImageBackgroundRenderer(),
        SceneBackgroundKind.solid: SolidBackgroundRenderer(),
      },
      motions: const {SceneMotionPreset.none: FadeMotionBuilder()},
    ),
    components: StandardGreeterComponents.new,
  );
}
