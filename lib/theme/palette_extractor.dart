import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Edge length used when downsampling the wallpaper before sampling.
const _sampleSize = 60;

/// Hue buckets of 10 degrees each.
const _bucketCount = 36;

/// A pixel must be this colorful and this bright to vote for a hue.
const _minSaturation = 0.3;
const _minValue = 0.15;

/// The extracted accent is desaturated and brightened into this range so the
/// greeter keeps a consistent contrast over any wallpaper.
const _accentSaturationScale = 0.9;
const _minAccentSaturation = 0.35;
const _maxAccentSaturation = 0.55;
const _accentValue = 0.95;

const _lightNeutralAccent = Color(0xffd0d0d0);
const _darkNeutralAccent = Color(0xff404040);

/// Extracts a Material You style accent from a bundled wallpaper asset.
///
/// Ports the Pixie SDDM hue histogram: the image is squashed into a small
/// sample grid, only colorful and sufficiently bright pixels vote, and the
/// dominant hue wins. Saturation and value are then clamped to the reference
/// theme range.
Future<Color> extractAccent(String asset) async {
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
    return _lightNeutralAccent;
  }
  return calculateAccentFromRgba(
    rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
  );
}

/// Picks the dominant vibrant hue from tightly packed RGBA bytes.
///
/// Returns a neutral accent when no pixel is colorful enough for a hue to be
/// meaningful, choosing light or dark by the wallpaper's average brightness.
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
    return averageBrightness < 0.5 ? _lightNeutralAccent : _darkNeutralAccent;
  }

  // Red wraps between the last and first bucket; merge both the weight and
  // the strongest sample so the winner always has a color to report.
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
