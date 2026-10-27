import 'package:flutter/widgets.dart';
import 'package:scene_schema/scene_schema.dart';

typedef SceneImageProviderResolver = ImageProvider Function(String asset);

class BackgroundParameter {
  const BackgroundParameter({
    required this.id,
    required this.label,
    required this.minimum,
    required this.maximum,
    required this.defaultValue,
  });
  final String id;
  final String label;
  final double minimum;
  final double maximum;
  final double defaultValue;
  double getValue(SceneBackground background) =>
      (background.parameters[id] ?? defaultValue).clamp(minimum, maximum);
}

abstract class BackgroundRenderer {
  const BackgroundRenderer();

  Widget build(BuildContext context, SceneBackground background);
  List<BackgroundParameter> get parameters => const [];

  /// Hosts can supply file-backed images while preserving a theme's atmosphere
  /// and composition. Renderers without image resources retain their instance.
  BackgroundRenderer getWithImageResolver(
    SceneImageProviderResolver resolveImage,
  ) => this;
}
