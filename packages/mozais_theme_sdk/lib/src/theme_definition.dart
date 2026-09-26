import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'greeter_host.dart';
import 'theme_components.dart';

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

  Widget buildScene({
    required GreeterHost host,
    required Set<ScenePredicate> activePredicates,
    required ValueListenable<Set<ScenePredicate>> activePredicatesListenable,
    required Animation<double> wakeProgress,
  }) {
    final components = this.components(
      GreeterThemeContext(host: host, tokens: tokens),
    );
    final backgroundBlurSigma = wakeProgress
        .drive(CurveTween(curve: Curves.easeOutCubic))
        .drive(Tween<double>(begin: 0, end: document.background.blurSigma));
    return SceneRuntime(
      document: document,
      theme: bundle,
      activePredicates: activePredicates,
      activePredicatesListenable: activePredicatesListenable,
      backgroundBlurSigma: backgroundBlurSigma,
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
