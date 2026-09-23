import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import 'background_renderer.dart';

/// Resolves a document asset path to an [ImageProvider].
///
/// The default reads from the Flutter asset bundle; a host without the assets
/// in its bundle can supply a file-based resolver instead.
typedef SceneImageProviderResolver = ImageProvider Function(String asset);

ImageProvider _assetImageProvider(String asset) => AssetImage(asset);

class ImageBackgroundRenderer extends BackgroundRenderer {
  const ImageBackgroundRenderer({this.resolveImage = _assetImageProvider});

  final SceneImageProviderResolver resolveImage;

  @override
  Widget build(BuildContext context, SceneBackground background) {
    final asset = background.asset;
    if (asset == null) {
      return SolidBackgroundRenderer().build(context, background);
    }

    Widget image = Image(
      image: resolveImage(asset),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return SolidBackgroundRenderer().build(context, background);
      },
    );
    if (background.blurSigma > 0) {
      // ImageFiltered paints outside the child's bounds; clip it so a larger
      // sigma does not grow the background beyond the scene rectangle.
      image = ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: background.blurSigma,
            sigmaY: background.blurSigma,
            tileMode: TileMode.clamp,
          ),
          child: image,
        ),
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
