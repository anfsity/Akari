import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_greeter/theme/palette_extractor.dart';

void main() {
  test('picks the dominant vibrant hue and clamps it to the accent range', () {
    final accent = calculateAccentFromRgba(
      _rgba([
        ...List.filled(100, const [255, 0, 0]),
        ...List.filled(10, const [0, 0, 255]),
      ]),
    );

    final hsv = HSVColor.fromColor(accent);
    expect(hsv.hue, closeTo(0, 1));
    expect(hsv.saturation, closeTo(0.55, 0.001));
    expect(hsv.value, closeTo(0.95, 0.001));
  });

  test('merges the red wrap bucket so near-360 hues still win', () {
    final accent = calculateAccentFromRgba(
      _rgba(List.filled(100, const [255, 0, 40])),
    );

    final hsv = HSVColor.fromColor(accent);
    expect(hsv.hue, greaterThan(350));
  });

  test('falls back to a light accent for a dark monochrome wallpaper', () {
    final accent = calculateAccentFromRgba(
      _rgba(List.filled(100, const [0, 0, 0])),
    );

    expect(accent, const Color(0xffd0d0d0));
  });

  test('falls back to a dark accent for a light monochrome wallpaper', () {
    final accent = calculateAccentFromRgba(
      _rgba(List.filled(100, const [255, 255, 255])),
    );

    expect(accent, const Color(0xff404040));
  });

  test('returns a neutral accent for empty input', () {
    expect(calculateAccentFromRgba(Uint8List(0)), const Color(0xffd0d0d0));
  });
}

Uint8List _rgba(List<List<int>> pixels) {
  final bytes = Uint8List(pixels.length * 4);
  for (var i = 0; i < pixels.length; i++) {
    bytes[i * 4] = pixels[i][0];
    bytes[i * 4 + 1] = pixels[i][1];
    bytes[i * 4 + 2] = pixels[i][2];
    bytes[i * 4 + 3] = 255;
  }
  return bytes;
}
