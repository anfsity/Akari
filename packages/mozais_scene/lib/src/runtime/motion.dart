import 'package:flutter/widgets.dart';

import '../model/scene_document.dart';

class SceneMotionSpec {
  const SceneMotionSpec({
    required this.preset,
    required this.duration,
    required this.curve,
    required this.reducedMotion,
  });

  final SceneMotionPreset preset;
  final Duration duration;
  final Curve curve;
  final bool reducedMotion;
}

abstract class SceneMotionBuilder {
  const SceneMotionBuilder();

  Widget build(BuildContext context, SceneMotionSpec spec, Widget child);
}
