import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:scene_schema/scene_schema.dart';

import 'background_renderer.dart';

ImageProvider _getAssetImageProvider(String asset) => AssetImage(asset);

class ImageBackgroundRenderer extends BackgroundRenderer {
  const ImageBackgroundRenderer({
    this.resolveImage = _getAssetImageProvider,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.high,
  });

  final SceneImageProviderResolver resolveImage;

  /// Focal point retained when cover fitting crops a wide wallpaper.
  final Alignment alignment;

  final FilterQuality filterQuality;

  @override
  ImageBackgroundRenderer getWithImageResolver(
    SceneImageProviderResolver resolveImage,
  ) => ImageBackgroundRenderer(
    resolveImage: resolveImage,
    alignment: alignment,
    filterQuality: filterQuality,
  );

  @override
  Widget build(BuildContext context, SceneBackground background) {
    final asset = background.asset;
    if (asset == null) {
      return const SolidBackgroundRenderer().build(context, background);
    }

    final image = Image(
      image: resolveImage(asset),
      fit: BoxFit.cover,
      alignment: alignment,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return const SolidBackgroundRenderer().build(context, background);
      },
    );
    return SceneBackgroundEffects(background: background, child: image);
  }
}

/// Atmosphere is shared by image and authored shader backgrounds.
class SceneBackgroundEffects extends StatelessWidget {
  const SceneBackgroundEffects({
    required this.background,
    required this.child,
    super.key,
  });
  final SceneBackground background;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ImageFiltered paints outside the child's bounds; clip it so a larger
        // sigma does not grow the background beyond the scene rectangle.
        // Keep the wrapper mounted across sigma == 0 transitions so stateful
        // shader or image children are not unmounted during wake/sleep ramps.
        ClipRect(
          child: ImageFiltered(
            enabled: background.blurSigma > 0,
            imageFilter: ui.ImageFilter.blur(
              sigmaX: background.blurSigma,
              sigmaY: background.blurSigma,
              tileMode: TileMode.clamp,
            ),
            child: child,
          ),
        ),
        ColoredBox(
          color: Color(background.color)
              .withValues(alpha: background.scrimOpacity),
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
