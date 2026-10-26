import 'package:flutter/material.dart';

const presetInk = Color(0xff20202d);
const presetPaper = Color(0xffd9e2ee);
const presetFont = 'packages/theme_preset1/SpaceGrotesk';

const presetCanvasSize = Size(1920, 1080);

double calculatePresetNightTop(double x) =>
    920 - x * 710 / presetCanvasSize.width;

Path getPresetNightPath() => Path()
  ..moveTo(0, calculatePresetNightTop(0))
  ..lineTo(
    presetCanvasSize.width,
    calculatePresetNightTop(presetCanvasSize.width),
  )
  ..lineTo(presetCanvasSize.width, presetCanvasSize.height)
  ..lineTo(0, presetCanvasSize.height)
  ..close();
