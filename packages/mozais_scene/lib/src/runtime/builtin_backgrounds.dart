import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import 'background_renderer.dart';

class ImageBackgroundRenderer extends BackgroundRenderer {
  const ImageBackgroundRenderer();

  @override
  Widget build(BuildContext context, SceneBackground background) {
    final asset = background.asset;
    if (asset == null) {
      return SolidBackgroundRenderer().build(context, background);
    }

    Widget image = Image.asset(
      asset,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return SolidBackgroundRenderer().build(context, background);
      },
    );
    if (background.blurSigma > 0) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: background.blurSigma,
          sigmaY: background.blurSigma,
          tileMode: TileMode.clamp,
        ),
        child: image,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        ColoredBox(
          color: Color(background.color).withValues(
            alpha: background.scrimOpacity.clamp(0, 1),
          ),
        ),
      ],
    );
  }
}

class SolidBackgroundRenderer extends BackgroundRenderer {
  const SolidBackgroundRenderer();

  @override
  Widget build(BuildContext context, SceneBackground background) {
    return ColoredBox(color: Color(background.color));
  }
}
