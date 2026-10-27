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

Duration getSceneMotionDuration(SceneNode node, Duration fallback) {
  var duration = node.motionTiming.durationMs ?? fallback.inMilliseconds;
  for (final track in node.tracks) {
    if (track.keyframes.last.timeMs > duration) {
      duration = track.keyframes.last.timeMs;
    }
  }
  return Duration(milliseconds: duration + node.motionTiming.delayMs);
}

Curve getSceneMotionCurve(SceneNode node, Duration duration, Curve fallback) {
  final curve = node.motionTiming.curve;
  final easing = curve == null
      ? fallback
      : Cubic(curve.x1, curve.y1, curve.x2, curve.y2);
  final total = getSceneMotionDuration(node, duration).inMilliseconds;
  if (total == 0) return const Threshold(0);
  final start = node.motionTiming.delayMs / total;
  final end =
      (node.motionTiming.delayMs +
          (node.motionTiming.durationMs ?? duration.inMilliseconds)) /
      total;
  return Interval(start, end, curve: easing);
}

/// Deterministic property evaluation used for live playback and the scrubber.
double calculateSceneTrackValue(SceneMotionTrack track, Duration elapsed) {
  final time = elapsed.inMicroseconds / 1000;
  final frames = track.keyframes;
  if (time <= frames.first.timeMs) return frames.first.value;
  for (var i = 1; i < frames.length; i++) {
    final end = frames[i];
    final start = frames[i - 1];
    if (time == end.timeMs) return end.value;
    if (time <= end.timeMs) {
      final fraction = (time - start.timeMs) / (end.timeMs - start.timeMs);
      final progress = switch (start.curve) {
        SceneKeyframeCurve.linear => fraction,
        SceneKeyframeCurve.easeInOut => Curves.easeInOut.transform(fraction),
        SceneKeyframeCurve.hold => time < end.timeMs ? 0.0 : 1.0,
      };
      return start.value + (end.value - start.value) * progress;
    }
  }
  return frames.last.value;
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
