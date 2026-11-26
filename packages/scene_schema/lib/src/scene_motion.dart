import 'collections.dart';
import 'scene_condition.dart';

const maxSceneMotionTimeMs = 60000;
const maxSceneKeyframeMagnitude = 100000.0;

enum SceneMotionPreset {
  none,
  fade,
  fadeSlide,
  fadeScale,
  hoverLift,
  focusGlow,
}

enum SceneStateEffect { shake, pulse }

class SceneStateTransition {
  const SceneStateTransition({
    required this.source,
    required this.target,
    required this.effect,
    this.timing = const SceneMotionTiming(),
  });

  final SceneCondition source;
  final SceneCondition target;
  final SceneStateEffect effect;
  final SceneMotionTiming timing;

  @override
  bool operator ==(Object other) =>
      other is SceneStateTransition &&
      other.source == source &&
      other.target == target &&
      other.effect == effect &&
      other.timing == timing;

  @override
  int get hashCode => Object.hash(source, target, effect, timing);
}

class SceneCubicBezier {
  const SceneCubicBezier(this.x1, this.y1, this.x2, this.y2);

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  @override
  bool operator ==(Object other) =>
      other is SceneCubicBezier &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2;

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2);
}

class SceneMotionTiming {
  const SceneMotionTiming({this.durationMs, this.delayMs = 0, this.curve});

  final int? durationMs;
  final int delayMs;
  final SceneCubicBezier? curve;

  bool get isDefault => durationMs == null && delayMs == 0 && curve == null;

  @override
  bool operator ==(Object other) =>
      other is SceneMotionTiming &&
      other.durationMs == durationMs &&
      other.delayMs == delayMs &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(durationMs, delayMs, curve);
}

enum SceneMotionProperty { opacity, translateX, translateY, scale, rotation }

enum SceneKeyframeCurve { linear, easeInOut, hold }

class SceneKeyframe {
  const SceneKeyframe({
    required this.timeMs,
    required this.value,
    this.curve = SceneKeyframeCurve.linear,
  });

  final int timeMs;
  final double value;

  /// Easing from this frame to the next frame.
  final SceneKeyframeCurve curve;

  @override
  bool operator ==(Object other) =>
      other is SceneKeyframe &&
      other.timeMs == timeMs &&
      other.value == value &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(timeMs, value, curve);
}

class SceneMotionTrack {
  const SceneMotionTrack({required this.property, required this.keyframes});

  final SceneMotionProperty property;
  final List<SceneKeyframe> keyframes;

  @override
  bool operator ==(Object other) =>
      other is SceneMotionTrack &&
      other.property == property &&
      listEquals(other.keyframes, keyframes);

  @override
  int get hashCode => Object.hash(property, Object.hashAll(keyframes));
}

double clampSceneKeyframeValue(SceneMotionProperty property, double value) =>
    property == SceneMotionProperty.opacity
    ? value.clamp(0.0, 1.0)
    : value.clamp(-maxSceneKeyframeMagnitude, maxSceneKeyframeMagnitude);
