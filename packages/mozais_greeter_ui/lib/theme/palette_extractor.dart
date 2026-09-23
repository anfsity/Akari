import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Edge length used when downsampling the wallpaper before sampling.
const _sampleSize = 60;

const _bucketCount = 36;
const _minSaturation = 0.3;
const _minValue = 0.15;
const _accentSaturationScale = 0.9;
const _minAccentSaturation = 0.35;
const _maxAccentSaturation = 0.55;
const _accentValue = 0.95;

const _lightNeutralAccent = Color(0xffd0d0d0);
const _darkNeutralAccent = Color(0xff404040);

/// Extracts a palette seed from a wallpaper asset.
///
/// The dominant vibrant hue is normalized before [ColorScheme.fromSeed]
/// builds the theme's tonal palette.
Future<Color> extractSeed(String asset) async {
  final data = await rootBundle.load(asset);
  return extractSeedFromBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

/// Extracts the dominant accent from image bytes, including editor imports
/// that have not been added to Flutter's asset bundle.
Future<Color> extractSeedFromBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: _sampleSize,
    targetHeight: _sampleSize,
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  codec.dispose();
  if (rgba == null) {
    return _lightNeutralAccent;
  }
  return calculateAccentFromRgba(
    rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
  );
}

/// Picks the dominant vibrant hue from tightly packed RGBA bytes.
Color calculateAccentFromRgba(Uint8List rgba) {
  final histogram = List<double>.filled(_bucketCount, 0);
  final samples = List<HSVColor?>.filled(_bucketCount, null);
  var vibrantFound = false;
  var brightnessTotal = 0.0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final red = rgba[i];
    final green = rgba[i + 1];
    final blue = rgba[i + 2];
    brightnessTotal += (0.299 * red + 0.587 * green + 0.114 * blue) / 255;

    final hsv = HSVColor.fromColor(Color.fromARGB(255, red, green, blue));
    if (hsv.saturation <= _minSaturation || hsv.value <= _minValue) {
      continue;
    }

    final bucket = (hsv.hue / 10).floor() % _bucketCount;
    final weight = hsv.saturation * hsv.value;
    histogram[bucket] += weight;
    final sample = samples[bucket];
    if (sample == null || weight > sample.saturation * sample.value) {
      samples[bucket] = hsv;
    }
    vibrantFound = true;
  }

  if (!vibrantFound) {
    final pixelCount = rgba.length ~/ 4;
    final averageBrightness = pixelCount == 0
        ? 0.0
        : brightnessTotal / pixelCount;
    return averageBrightness < 0.5
        ? _lightNeutralAccent
        : _darkNeutralAccent;
  }

  final wrapSample = samples[_bucketCount - 1];
  if (wrapSample != null &&
      (samples[0] == null ||
          wrapSample.saturation * wrapSample.value >
              samples[0]!.saturation * samples[0]!.value)) {
    samples[0] = wrapSample;
  }
  histogram[0] += histogram[_bucketCount - 1];

  var winner = -1;
  var maxWeight = -1.0;
  for (var bucket = 0; bucket < _bucketCount - 1; bucket++) {
    if (histogram[bucket] > maxWeight) {
      maxWeight = histogram[bucket];
      winner = bucket;
    }
  }

  final sample = winner == -1 ? null : samples[winner];
  if (sample == null) {
    return _lightNeutralAccent;
  }
  final saturation = (sample.saturation * _accentSaturationScale).clamp(
    _minAccentSaturation,
    _maxAccentSaturation,
  );
  return HSVColor.fromAHSV(1, sample.hue, saturation, _accentValue).toColor();
}
