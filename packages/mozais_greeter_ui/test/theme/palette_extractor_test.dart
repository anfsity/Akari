import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_greeter_ui/theme/palette_extractor.dart';

void main() {
  test('selects a dominant vibrant hue from the sampled pixels', () {
    final seed = calculateAccentFromRgba(
      _rgba(const [
        [0, 0, 0],
        [255, 255, 255],
        [100, 50, 200],
        [0, 0, 0],
      ]),
    );

    expect(seed, HSVColor.fromAHSV(1, 260, 0.55, 0.95).toColor());
  });

  test('uses a neutral accent for empty input', () {
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
