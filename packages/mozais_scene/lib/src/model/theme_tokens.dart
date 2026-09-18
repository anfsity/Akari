import 'package:flutter/material.dart';

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
    required this.shortMotion,
    required this.mediumMotion,
    required this.standardCurve,
    required this.minHitTarget,
    required this.maxInteractiveRotationDegrees,
    required this.minTextScale,
    required this.allowBlur,
    required this.blurSigma,
    required this.glassColor,
    required this.scrimColor,
  });

  final ThemeData materialTheme;
  final EdgeInsets pagePadding;
  final EdgeInsets panelPadding;
  final double contentMaxWidth;
  final double controlHeight;
  final double panelRadius;
  final double sectionGap;
  final double controlGap;
  final Duration shortMotion;
  final Duration mediumMotion;
  final Curve standardCurve;
  final double minHitTarget;
  final double maxInteractiveRotationDegrees;
  final double minTextScale;
  final bool allowBlur;
  final double blurSigma;
  final Color glassColor;
  final Color scrimColor;
}
