import 'package:flutter/material.dart';

/// Design values consumed by Scene and Visual layers.
///
/// This class intentionally contains no authentication or backend policy.
class ThemeTokens {
  const ThemeTokens({
    required this.materialTheme,
    required this.pagePadding,
    required this.panelPadding,
    required this.contentMaxWidth,
    required this.controlHeight,
    required this.panelRadius,
    required this.sectionGap,
    required this.controlGap,
    required this.authenticationActionGap,
    required this.promptActionGap,
  });

  factory ThemeTokens.dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff78c7c9),
      brightness: Brightness.dark,
    );

    return ThemeTokens(
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
      panelPadding: const EdgeInsets.all(30),
      contentMaxWidth: 460,
      controlHeight: 52,
      panelRadius: 8,
      sectionGap: 24,
      controlGap: 12,
      authenticationActionGap: 28,
      promptActionGap: 20,
    );
  }

  final ThemeData materialTheme;
  final EdgeInsets pagePadding;
  final EdgeInsets panelPadding;
  final double contentMaxWidth;
  final double controlHeight;
  final double panelRadius;
  final double sectionGap;
  final double controlGap;
  final double authenticationActionGap;
  final double promptActionGap;
}
