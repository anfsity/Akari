import 'package:flutter/material.dart';

import '../model/scene_document.dart';
import 'background_renderer.dart';

class ImageBackgroundRenderer extends BackgroundRenderer {
  const ImageBackgroundRenderer();

  @override
  Widget build(BuildContext context, SceneBackground background) {
    final asset = background.asset;
    if (asset == null) {
      return SolidBackgroundRenderer().build(context, background);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          asset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return SolidBackgroundRenderer().build(context, background);
          },
        ),
        ColoredBox(
          color: background.color.withValues(
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
    return ColoredBox(color: background.color);
  }
}
