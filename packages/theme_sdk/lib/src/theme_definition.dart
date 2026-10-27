import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:scene/scene.dart';

import 'greeter_host.dart';
import 'palette_extractor.dart';
import 'theme_components.dart';
import 'theme_customization.dart';
import 'theme_layout.dart';
import 'theme_presets.dart';

/// Studio supplies its authored document; the production host omits it to use
/// the package's generated scene. Both paths must resolve the same choices.
typedef ThemeBuilder = ThemeDefinition Function({
  Color? seed,
  SceneDocument? document,
});

/// Complete compile-time theme bundle: its scene, component implementation,
/// and visual runtime configuration are constructed together by its package.
class ThemeDefinition {
  const ThemeDefinition({
    required this.id,
    required this.document,
    required this.bundle,
    required this.components,
    this.componentCatalog = const ThemeComponentCatalog(),
    this.presetCatalog = const ThemePresetCatalog(),
    this.layout,
  });

  final String id;
  final SceneDocument document;
  final ThemeBundle bundle;
  final GreeterThemeComponentsFactory components;
  final ThemeComponentCatalog componentCatalog;
  final ThemePresetCatalog presetCatalog;
  final ThemeLayoutDefinition? layout;

  ThemeTokens get tokens => bundle.tokens;

  ThemeData get materialTheme => bundle.materialTheme;

  Future<Color?> findBackgroundSeed() async {
    final asset = document.background.asset;
    if (asset == null) {
      return null;
    }
    try {
      return await extractSeed(asset);
    } on Object {
      // Palette extraction is optional decoration. Missing or undecodable
      // wallpaper must leave the theme's authored default palette usable.
      return null;
    }
  }

  Widget buildScene({
    required GreeterHost host,
    required Set<ScenePredicate> activePredicates,
    required ValueListenable<Set<ScenePredicate>> activePredicatesListenable,
    required Animation<double> wakeProgress,
  }) {
    final components = this.components(
      GreeterThemeContext(host: host, tokens: tokens, canvas: document.canvas),
    );
    return SceneRuntime(
      document: document,
      theme: bundle,
      activePredicates: activePredicates,
      activePredicatesListenable: activePredicatesListenable,
      backgroundBlurSigma: getBackgroundBlurAnimation(
        document.background,
        wakeProgress,
      ),
      // Prepare input and picker subtrees before wake to reduce first-response
      // work. Hidden components stay mounted, so their timers/listeners must
      // remain cheap even when pointer, focus, and semantics are excluded.
      prewarmHiddenNodes: true,
      nodeBuilder: components.build,
    );
  }

  ThemeDefinition copyWith({
    String? id,
    SceneDocument? document,
    ThemeBundle? bundle,
  }) {
    return ThemeDefinition(
      id: id ?? this.id,
      document: document ?? this.document,
      bundle: bundle ?? this.bundle,
      components: components,
      componentCatalog: componentCatalog,
      presetCatalog: presetCatalog,
      layout: layout,
    );
  }
}

/// Studio and the production scene share the same wake-dependent frost. A sharp
/// background must not rebuild its renderer on every transition frame.
Animation<double>? getBackgroundBlurAnimation(
  SceneBackground background,
  Animation<double> wakeProgress,
) => background.blurSigma == 0
    ? null
    : wakeProgress
          .drive(CurveTween(curve: Curves.easeOutCubic))
          .drive(Tween<double>(begin: 0, end: background.blurSigma));
