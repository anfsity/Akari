import 'package:flutter/widgets.dart';
import 'package:scene_schema/scene_schema.dart';

typedef SceneImageProviderResolver = ImageProvider Function(String asset);

abstract class BackgroundRenderer {
  const BackgroundRenderer();

  Widget build(BuildContext context, SceneBackground background);

  /// Hosts can supply file-backed images while preserving a theme's atmosphere
  /// and composition. Renderers without image resources retain their instance.
  BackgroundRenderer getWithImageResolver(
    SceneImageProviderResolver resolveImage,
  ) => this;
}
