import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:scene/scene.dart';

import 'greeter_host.dart';
import 'palette_extractor.dart';
import 'theme_components.dart';

typedef ThemeBuilder = ThemeDefinition Function({Color? seed});

/// Complete compile-time theme bundle: its scene, component implementation,
/// and visual runtime configuration are constructed together by its package.
class ThemeDefinition {
  const ThemeDefinition({
    required this.id,
    required this.document,
    required this.bundle,
    required this.components,
  });

  final String id;
  final SceneDocument document;
  final ThemeBundle bundle;
  final GreeterThemeComponentsFactory components;

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
      GreeterThemeContext(host: host, tokens: tokens),
    );
    // A sharp background has no wake-dependent work. Subscribing to a constant
    // zero tween would rebuild its renderer on every transition frame.
    final backgroundBlurSigma = document.background.blurSigma == 0
        ? null
        : wakeProgress
              .drive(CurveTween(curve: Curves.easeOutCubic))
              .drive(
                Tween<double>(begin: 0, end: document.background.blurSigma),
              );
    return SceneRuntime(
      document: document,
      theme: bundle,
      activePredicates: activePredicates,
      activePredicatesListenable: activePredicatesListenable,
      backgroundBlurSigma: backgroundBlurSigma,
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
    );
  }
}
