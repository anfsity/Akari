import 'dart:math' as math;

import 'package:theme_sdk/theme_sdk.dart';

typedef TimelineTrackTarget = ({
  SceneNode node,
  int trackIndex,
  SceneMotionTrack track,
});

SceneNode addDefaultTimelineTrack(
  SceneNode node,
  SceneMotionProperty property,
) {
  if (node.tracks.any((track) => track.property == property)) return node;
  final start = switch (property) {
    SceneMotionProperty.opacity => 0.0,
    SceneMotionProperty.scale => .8,
    _ => 0.0,
  };
  final end = switch (property) {
    SceneMotionProperty.opacity || SceneMotionProperty.scale => 1.0,
    SceneMotionProperty.rotation => 360.0,
    _ => 100.0,
  };
  return node.copyWith(
    tracks: [
      ...node.tracks,
      SceneMotionTrack(
        property: property,
        keyframes: [
          SceneKeyframe(timeMs: 0, value: start),
          SceneKeyframe(timeMs: 1000, value: end),
        ],
      ),
    ],
  );
}

SceneNode insertTimelineKeyframe(
  SceneNode node,
  SceneMotionProperty property,
  Duration elapsed,
) {
  final index = node.tracks.indexWhere((track) => track.property == property);
  if (index < 0) return node;
  final track = node.tracks[index];
  final time = (elapsed.inMilliseconds - node.motionTiming.delayMs).clamp(
    0,
    maxSceneMotionTimeMs,
  );
  if (track.keyframes.any((frame) => frame.timeMs == time)) return node;
  final frames = [
    ...track.keyframes,
    SceneKeyframe(
      timeMs: time,
      value: calculateSceneTrackValue(track, Duration(milliseconds: time)),
    ),
  ]..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  return node.copyWith(
    tracks: [...node.tracks]
      ..[index] = SceneMotionTrack(property: track.property, keyframes: frames),
  );
}

SceneNode shiftTimelineNodeDelay(SceneNode source, int deltaMs) =>
    source.copyWith(
      motionTiming: SceneMotionTiming(
        delayMs: (source.motionTiming.delayMs + deltaMs).clamp(
          0,
          maxSceneMotionTimeMs,
        ),
        durationMs: source.motionTiming.durationMs,
        curve: source.motionTiming.curve,
      ),
    );

SceneNode resizeTimelineNodeDuration(
  SceneNode source,
  Duration fallbackDuration,
  int deltaMs,
) {
  final span =
      getSceneMotionDuration(source, fallbackDuration).inMilliseconds -
      source.motionTiming.delayMs;
  final minimum = source.tracks.fold<int>(
    1,
    (value, track) => math.max(value, track.keyframes.length - 1),
  );
  final duration = (span + deltaMs).clamp(minimum, maxSceneMotionTimeMs);
  return source.copyWith(
    tracks: [
      for (final track in source.tracks)
        _scaleTrackKeyframes(track, span, duration),
    ],
    motionTiming: SceneMotionTiming(
      durationMs: duration,
      delayMs: source.motionTiming.delayMs,
      curve: source.motionTiming.curve,
    ),
  );
}

SceneMotionTrack _scaleTrackKeyframes(
  SceneMotionTrack track,
  int sourceSpan,
  int targetDuration,
) {
  var previous = -1;
  final frames = <SceneKeyframe>[];
  for (var i = 0; i < track.keyframes.length; i++) {
    final frame = track.keyframes[i];
    final scaled = sourceSpan == 0
        ? 0
        : (frame.timeMs * targetDuration / sourceSpan).round();
    final time = scaled.clamp(
      previous + 1,
      targetDuration - (track.keyframes.length - 1 - i),
    );
    frames.add(
      SceneKeyframe(timeMs: time, value: frame.value, curve: frame.curve),
    );
    previous = time;
  }
  return SceneMotionTrack(property: track.property, keyframes: frames);
}

SceneNode retimeTimelineKeyframe(
  SceneNode source,
  int trackIndex,
  int frameIndex,
  int deltaMs,
) {
  final track = source.tracks[trackIndex];
  final frame = track.keyframes[frameIndex];
  final min = frameIndex == 0 ? 0 : track.keyframes[frameIndex - 1].timeMs + 1;
  final max = frameIndex == track.keyframes.length - 1
      ? maxSceneMotionTimeMs
      : track.keyframes[frameIndex + 1].timeMs - 1;
  final frames = [...track.keyframes]
    ..[frameIndex] = SceneKeyframe(
      timeMs: (frame.timeMs + deltaMs).clamp(min, max),
      value: frame.value,
      curve: frame.curve,
    );
  return source.copyWith(
    tracks: [...source.tracks]
      ..[trackIndex] = SceneMotionTrack(
        property: track.property,
        keyframes: frames,
      ),
  );
}

TimelineTrackTarget? findTimelineTrackTarget(
  SceneDocument document,
  String nodeId,
  SceneMotionProperty property,
  int frameIndex,
) {
  if (frameIndex < 0) return null;
  final node = document.nodes.where((entry) => entry.id == nodeId).firstOrNull;
  if (node == null) return null;
  final trackIndex = node.tracks.indexWhere(
    (track) => track.property == property,
  );
  if (trackIndex < 0) return null;
  final track = node.tracks[trackIndex];
  if (frameIndex >= track.keyframes.length) return null;
  return (node: node, trackIndex: trackIndex, track: track);
}

SceneNode replaceOrRemoveTimelineKeyframe(
  SceneNode node,
  int trackIndex,
  int frameIndex,
  SceneKeyframe? replacement,
) {
  final track = node.tracks[trackIndex];
  final frames = [...track.keyframes];
  if (replacement != null) {
    frames[frameIndex] = replacement;
  } else {
    frames.removeAt(frameIndex);
  }
  final tracks = [...node.tracks];
  if (frames.isEmpty) {
    tracks.removeAt(trackIndex);
  } else {
    tracks[trackIndex] = SceneMotionTrack(
      property: track.property,
      keyframes: frames,
    );
  }
  return node.copyWith(tracks: tracks);
}
