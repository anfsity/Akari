import 'package:flutter/material.dart';

class ThemeTokens {
  const ThemeTokens({
    required this.materialTheme,
    required this.panelRadius,
    required this.mediumMotion,
    required this.standardCurve,
    required this.minHitTarget,
    required this.surfaceColor,
    required this.surfaceVariantColor,
  });

  final ThemeData materialTheme;

  /// Corner radius shared by panel surfaces.
  final double panelRadius;

  /// Duration used by scene motion presets.
  final Duration mediumMotion;

  /// Curve used by scene motion presets.
  final Curve standardCurve;

  /// Minimum touch target enforced for interactive scene nodes.
  final double minHitTarget;

  /// Fill for inset surfaces such as the credential field, avatar fallback,
  /// and session pill.
  final Color surfaceColor;

  /// Elevated surface for pill borders and pressed or open states.
  final Color surfaceVariantColor;
}
