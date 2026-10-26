import 'package:flutter/material.dart';
import 'package:scene/scene.dart';
import 'package:theme_sdk/theme_sdk.dart' show ThemeDefinition;

import 'default.scene.g.dart';
import 'terrace_components.dart';
import 'terrace_visuals.dart';
import 'theme_customization.dart';
import 'theme_layout.dart';

/// Seed used before extraction runs and when the wallpaper cannot be sampled.
const _fallbackSeed = Color(0xff83cddd);
const _fontFamily = 'packages/theme_default/SpaceGrotesk';
ThemeDefinition buildDefaultTheme({Color? seed, SceneDocument? document}) {
  final scene = document ?? defaultSceneDocument;
  terracePresetCatalog.validateDocument(scene);
  terraceComponentCatalog.validateDocument(scene);
  terraceLayout.validateDocument(scene);
  final palette = terracePalette.getValue(scene.themeProperties);
  final material = terraceMaterial.getValue(scene.themeProperties);
  final motion = terraceMotion.getValue(scene.themeProperties);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: switch (palette) {
      TerracePalette.wallpaper => seed ?? _fallbackSeed,
      TerracePalette.ocean => _fallbackSeed,
      TerracePalette.rose => const Color(0xfff4a6b9),
      TerracePalette.violet => const Color(0xffb7a2f7),
    },
    brightness: Brightness.dark,
  );
  final surface = switch (palette) {
    TerracePalette.wallpaper || TerracePalette.ocean => const Color(0xff25465e),
    TerracePalette.rose => const Color(0xff4c2b3a),
    TerracePalette.violet => const Color(0xff342e50),
  };
  final radius = switch (material) {
    TerraceMaterial.airy => 20.0,
    TerraceMaterial.frosted => 28.0,
    TerraceMaterial.solid => 8.0,
  };
  final text = colorScheme.onSurface;
  final tokens = ThemeTokens(
    materialTheme: ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: _fontFamily,
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            material == TerraceMaterial.airy ? 12 : radius,
          ),
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.2)),
        ),
        textStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 14,
          color: text,
        ),
      ),
      textTheme: Typography.whiteMountainView.apply(
        fontFamily: _fontFamily,
        bodyColor: text,
        displayColor: text,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: material != TerraceMaterial.airy,
        fillColor: switch (material) {
          TerraceMaterial.airy => Colors.transparent,
          TerraceMaterial.frosted => surface.withValues(alpha: 0.55),
          TerraceMaterial.solid => surface,
        },
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
          fontSize: 16,
        ),
        contentPadding: material == TerraceMaterial.airy
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 16),
        border: _getFieldBorder(
          colorScheme.outlineVariant,
          1,
          material,
          radius,
        ),
        enabledBorder: _getFieldBorder(
          Colors.white.withValues(alpha: 0.3),
          1,
          material,
          radius,
        ),
        focusedBorder: _getFieldBorder(
          colorScheme.primary,
          1.5,
          material,
          radius,
        ),
        disabledBorder: _getFieldBorder(
          colorScheme.outline.withValues(alpha: 0.3),
          1,
          material,
          radius,
        ),
        isDense: true,
      ),
      visualDensity: VisualDensity.standard,
    ),
    panelRadius: radius,
    mediumMotion: switch (motion) {
      TerraceMotion.terrace => const Duration(milliseconds: 420),
      TerraceMotion.gentle => const Duration(milliseconds: 280),
      TerraceMotion.none => Duration.zero,
    },
    standardCurve: Curves.linear,
    disableAnimations: motion == TerraceMotion.none,
    minHitTarget: 44,
    surfaceColor: surface,
    surfaceVariantColor: colorScheme.surfaceContainerHighest,
  );
  return ThemeDefinition(
    id: 'default',
    document: scene,
    componentCatalog: terraceComponentCatalog,
    presetCatalog: terracePresetCatalog,
    layout: terraceLayout,
    bundle: ThemeBundle(
      tokens: tokens,
      backgrounds: const {
        SceneBackgroundKind.image: TerraceBackgroundRenderer(),
        SceneBackgroundKind.solid: SolidBackgroundRenderer(),
      },
      motions: switch (motion) {
        TerraceMotion.none => const {},
        TerraceMotion.gentle => const {
          SceneMotionPreset.fade: FadeMotionBuilder(),
          SceneMotionPreset.fadeSlide: FadeMotionBuilder(),
          SceneMotionPreset.hoverLift: FadeMotionBuilder(),
          SceneMotionPreset.focusGlow: FadeMotionBuilder(),
        },
        TerraceMotion.terrace => const {
          SceneMotionPreset.fade: TerraceFadeMotion(),
          SceneMotionPreset.fadeSlide: TerraceEntranceMotion(),
          SceneMotionPreset.hoverLift: TerraceActionMotion(),
          SceneMotionPreset.focusGlow: FocusGlowMotionBuilder(),
        },
      },
    ),
    components: (context) => TerraceComponents(context, material: material),
  );
}

InputBorder _getFieldBorder(
  Color color,
  double width,
  TerraceMaterial material,
  double radius,
) {
  final side = BorderSide(color: color, width: width);
  return material == TerraceMaterial.airy
      ? UnderlineInputBorder(borderRadius: BorderRadius.zero, borderSide: side)
      : OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: side,
        );
}
