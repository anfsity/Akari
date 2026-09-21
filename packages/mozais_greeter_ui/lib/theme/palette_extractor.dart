import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Edge length used when downsampling the wallpaper before sampling.
const _sampleSize = 60;

/// Extracts a palette seed from a bundled wallpaper asset.
///
/// The seed is the average color of the downsampled image. Averaging keeps the
/// accent representative of the whole wallpaper instead of letting one small,
/// highly saturated region dominate; the theme then runs the seed through
/// [ColorScheme.fromSeed] to build a harmonized tonal palette.
Future<Color> extractSeed(String asset) async {
  final data = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    targetWidth: _sampleSize,
    targetHeight: _sampleSize,
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  codec.dispose();
  if (rgba == null) {
    return const Color(0xff000000);
  }
  return calculateSeedFromRgba(
    rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
  );
}

/// Returns the arithmetic mean color of tightly packed RGBA bytes.
Color calculateSeedFromRgba(Uint8List rgba) {
  var red = 0;
  var green = 0;
  var blue = 0;
  var count = 0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    red += rgba[i];
    green += rgba[i + 1];
    blue += rgba[i + 2];
    count++;
  }
  if (count == 0) {
    return const Color(0xff000000);
  }
  return Color.fromARGB(255, red ~/ count, green ~/ count, blue ~/ count);
}
