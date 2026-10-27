import 'package:flutter/widgets.dart';
import 'package:scene_schema/scene_schema.dart';

typedef SceneMotionSpec = ({
  SceneMotionPreset preset,
  Duration duration,
  Curve curve,
  bool reducedMotion,
});

/// Deterministic inspection of a transition, without advancing live controllers.
class ScenePlayback {
  const ScenePlayback({
    required this.elapsed,
    required this.from,
    this.enterAll = false,
  });
  final Duration elapsed;
  final Set<ScenePredicate> from;
  final bool enterAll;
}

Duration getSceneMotionDuration(SceneNode node, Duration fallback) => Duration(
  milliseconds:
      (node.motionTiming.durationMs ?? fallback.inMilliseconds) +
      node.motionTiming.delayMs,
);

Curve getSceneMotionCurve(SceneNode node, Duration duration, Curve fallback) {
  final curve = node.motionTiming.curve;
  final easing = curve == null
      ? fallback
      : Cubic(curve.x1, curve.y1, curve.x2, curve.y2);
  final total = getSceneMotionDuration(node, duration).inMilliseconds;
  return Interval(
    total == 0 ? 0 : node.motionTiming.delayMs / total,
    1,
    curve: easing,
  );
}

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
