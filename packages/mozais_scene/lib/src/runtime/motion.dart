import 'package:flutter/widgets.dart';

import '../model/scene_document.dart';

typedef SceneMotionSpec = ({
  SceneMotionPreset preset,
  Duration duration,
  Curve curve,
  bool reducedMotion,
});

abstract class SceneMotionBuilder {
  const SceneMotionBuilder();

  Widget build(BuildContext context, SceneMotionSpec spec, Widget child);
}
