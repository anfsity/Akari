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

  /// Whether this builder animates node presence.
  ///
  /// Builders that only apply a static or interaction effect return false so
  /// the runtime mounts and unmounts the node without waiting for a
  /// transition.
  bool get animatesPresence => true;

  /// Wraps [child] using [progress], where 0 is fully hidden and 1 is shown.
  ///
  /// [progress] is already curved; builders must not create or own animation
  /// controllers.
  Widget build(
    BuildContext context,
    SceneMotionSpec spec,
    Animation<double> progress,
    Widget child,
  );
}
