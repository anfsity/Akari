import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'preset1.scene.g.dart';
import 'preset_components.dart';
import 'preset_style.dart';
import 'preset_visuals.dart';

ThemeDefinition buildPreset1Theme({Color? seed}) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: presetPaper,
        brightness: Brightness.dark,
      ).copyWith(
        primary: presetPaper,
        onPrimary: presetInk,
        surface: presetInk,
        onSurface: presetPaper,
        error: const Color(0xfff1baba),
      );
  return ThemeDefinition(
    id: 'preset1',
    document: preset1SceneDocument,
    bundle: ThemeBundle(
      tokens: ThemeTokens(
        materialTheme: ThemeData(
          colorScheme: scheme,
          fontFamily: presetFont,
          scaffoldBackgroundColor: presetInk,
          splashFactory: NoSplash.splashFactory,
          textTheme: Typography.whiteMountainView.apply(
            fontFamily: presetFont,
            bodyColor: presetPaper,
            displayColor: presetPaper,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            filled: false,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            hintStyle: TextStyle(color: Color(0xffa9adbf), letterSpacing: 3),
            contentPadding: EdgeInsets.symmetric(horizontal: 16),
            isDense: true,
          ),
          popupMenuTheme: PopupMenuThemeData(
            color: const Color(0xff262633),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: const RoundedRectangleBorder(
              side: BorderSide(color: Color(0xff666979)),
            ),
            textStyle: const TextStyle(
              fontFamily: presetFont,
              color: presetPaper,
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: presetPaper,
              minimumSize: const Size(44, 44),
              shape: const RoundedRectangleBorder(),
            ),
          ),
        ),
        panelRadius: 0,
        mediumMotion: const Duration(milliseconds: 650),
        standardCurve: Curves.linear,
        minHitTarget: 44,
        surfaceColor: Colors.transparent,
        surfaceVariantColor: presetInk,
      ),
      backgrounds: const {
        SceneBackgroundKind.solid: PresetBackgroundRenderer(),
      },
      motions: const {
        SceneMotionPreset.fade: PresetPresenceMotion(),
        SceneMotionPreset.fadeSlide: PresetPresenceMotion(),
      },
    ),
    components: PresetComponents.new,
  );
}
