import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_preset1/preset_visuals.dart';

const _frameSize = Size(1920, 1080);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.FragmentProgram program;
  late ui.Image artwork;
  late ui.Image flatSurface;

  setUpAll(() async {
    program = await ui.FragmentProgram.fromAsset(
      'packages/theme_preset1/shaders/wet_surface.frag',
    );
    final recorder = ui.PictureRecorder();
    const PresetArtworkPainter().paint(Canvas(recorder), _frameSize);
    final picture = recorder.endRecording();
    artwork = await picture.toImage(1920, 1080);
    picture.dispose();

    final flatRecorder = ui.PictureRecorder();
    Canvas(flatRecorder).drawColor(const Color(0xff20202d), BlendMode.src);
    final flatPicture = flatRecorder.endRecording();
    flatSurface = await flatPicture.toImage(1920, 1080);
    flatPicture.dispose();
  });

  tearDownAll(() {
    artwork.dispose();
    flatSurface.dispose();
  });

  test('water flows while the diagonal pale field stays untouched', () async {
    final start = await _renderSurfaceFrame(program, artwork, 0);
    final flowing = await _renderSurfaceFrame(program, artwork, .5 / 120);
    var movingPixels = 0;
    var paleAlpha = 0;
    var nightAlpha = 255;
    for (var y = 0; y < 1080; y++) {
      for (var x = 0; x < 1920; x++) {
        final offset = (y * 1920 + x) * 4;
        if (y < 920 - x * 710 / 1920 - 2) {
          paleAlpha = math.max(
            paleAlpha,
            math.max(start[offset + 3], flowing[offset + 3]),
          );
        } else if (y > 920 - x * 710 / 1920 + 2) {
          nightAlpha = math.min(nightAlpha, start[offset + 3]);
          if ((start[offset] - flowing[offset]).abs() > 2) {
            movingPixels++;
          }
        }
      }
    }
    expect(paleAlpha, 0);
    expect(nightAlpha, 255);
    expect(movingPixels, greaterThan(20000));
  });

  test('sliding glass drops move even over an untextured surface', () async {
    final start = await _renderSurfaceFrame(program, flatSurface, 0);
    final sliding = await _renderSurfaceFrame(program, flatSurface, .5 / 120);
    var movingDropPixels = 0;
    for (var offset = 0; offset < start.length; offset += 4) {
      // Traveling water highlights add at most five levels on this flat
      // texture. Larger changes isolate the moving lenses and their trails.
      if ((start[offset] - sliding[offset]).abs() > 8) {
        movingDropPixels++;
      }
    }
    expect(movingDropPixels, greaterThan(100));
  });

  test('water and glass remain continuous across the weather loop', () async {
    final start = await _renderSurfaceFrame(program, artwork, 0);
    final wrapped = await _renderSurfaceFrame(program, artwork, 1);
    final beforeWrap = await _renderSurfaceFrame(
      program,
      artwork,
      1 - .001 / 120,
    );
    var wrapDifference = 0;
    var boundaryDifference = 0;
    for (var offset = 0; offset < start.length; offset++) {
      wrapDifference += (start[offset] - wrapped[offset]).abs();
      boundaryDifference += (start[offset] - beforeWrap[offset]).abs();
    }
    expect(wrapDifference / start.length, lessThan(.01));
    expect(boundaryDifference / start.length, lessThan(.05));
  });

  test('wet glass keeps its authored placement at a scaled viewport', () async {
    final full = await _renderSurfaceFrame(program, artwork, 0);
    final scaled = await _renderSurfaceFrame(
      program,
      artwork,
      0,
      size: const Size(960, 540),
    );
    expect(scaled[(150 * 960 + 200) * 4 + 3], 0);
    expect(scaled[(400 * 960 + 700) * 4 + 3], 255);
    var difference = 0.0;
    for (var y = 0; y < 540; y++) {
      for (var x = 0; x < 960; x++) {
        final source = (y * 2 * 1920 + x * 2) * 4;
        for (var channel = 0; channel < 3; channel++) {
          final average =
              (full[source + channel] +
                  full[source + 4 + channel] +
                  full[source + 1920 * 4 + channel] +
                  full[source + 1920 * 4 + 4 + channel]) /
              4;
          difference += (scaled[(y * 960 + x) * 4 + channel] - average).abs();
        }
      }
    }
    expect(difference / (960 * 540 * 3), lessThan(1));
  });
}

Future<Uint8List> _renderSurfaceFrame(
  ui.FragmentProgram program,
  ui.Image texture,
  double progress, {
  Size size = _frameSize,
}) async {
  final shader = program.fragmentShader()
    ..setImageSampler(0, texture, filterQuality: FilterQuality.low);
  final recorder = ui.PictureRecorder();
  PresetSurfacePainter(
    AlwaysStoppedAnimation(progress),
    shader,
  ).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  shader.dispose();
  return pixels!.buffer.asUint8List();
}
