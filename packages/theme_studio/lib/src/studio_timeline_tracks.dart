import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_form.dart';
import 'studio_form_values.dart';

const studioTimelineLabelWidth = 120.0;
const studioTimelineTrackPadding = 10.0;

/// Track gestures preview against a captured node and commit once on release.
class StudioTimelineTracks extends StatefulWidget {
  const StudioTimelineTracks({
    required this.editor,
    required this.duration,
    required this.elapsed,
    required this.fallbackDuration,
    super.key,
  });
  final SceneEditor editor;
  final Duration duration;
  final Duration elapsed;
  final Duration fallbackDuration;
  @override
  State<StudioTimelineTracks> createState() => _StudioTimelineTracksState();
}

class _StudioTimelineTracksState extends State<StudioTimelineTracks> {
  SceneMotionProperty _property = SceneMotionProperty.opacity;
  SceneNode? _source;
  SceneNode? _candidate;
  double _origin = 0;
  double _millisecondsPerPixel = 1;
  void _start(SceneNode node, DragStartDetails details, double width) {
    if (!widget.editor.applyDraft()) return;
    _source = node;
    _origin = details.globalPosition.dx;
    _millisecondsPerPixel = widget.duration.inMilliseconds / width;
  }

  void _preview(SceneNode node) {
    _candidate = node;
    widget.editor.previewNode(node);
  }

  void _commit() {
    if (_candidate case final node?) {
      widget.editor.updateNode(node);
    }
    _source = _candidate = null;
  }

  void _cancel() {
    widget.editor.cancelPreview();
    _source = _candidate = null;
  }

  int _delta(DragUpdateDetails details) =>
      ((details.globalPosition.dx - _origin) * _millisecondsPerPixel).round();

  void _addTrack() {
    final editor = widget.editor;
    if (!editor.applyDraft()) return;
    final node = editor.selectedNode;
    if (node.tracks.any((track) => track.property == _property)) return;
    final start = switch (_property) {
      SceneMotionProperty.opacity => 0.0,
      SceneMotionProperty.scale => .8,
      _ => 0.0,
    };
    final end = switch (_property) {
      SceneMotionProperty.opacity || SceneMotionProperty.scale => 1.0,
      SceneMotionProperty.rotation => 360.0,
      _ => 100.0,
    };
    editor.updateNode(
      node.copyWith(
        tracks: [
          ...node.tracks,
          SceneMotionTrack(
            property: _property,
            keyframes: [
              SceneKeyframe(timeMs: 0, value: start),
              SceneKeyframe(timeMs: 1000, value: end),
            ],
          ),
        ],
      ),
    );
  }

  void _addKeyframe() {
    final editor = widget.editor;
    if (!editor.applyDraft()) return;
    final node = editor.selectedNode;
    final index = node.tracks.indexWhere(
      (track) => track.property == _property,
    );
    if (index < 0) return;
    final track = node.tracks[index];
    final time = (widget.elapsed.inMilliseconds - node.motionTiming.delayMs)
        .clamp(0, 60000);
    if (track.keyframes.any((frame) => frame.timeMs == time)) return;
    final frames = [
      ...track.keyframes,
      SceneKeyframe(
        timeMs: time,
        value: calculateSceneTrackValue(track, Duration(milliseconds: time)),
      ),
    ]..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    editor.updateNode(
      node.copyWith(
        tracks: [...node.tracks]
          ..[index] = SceneMotionTrack(
            property: track.property,
            keyframes: frames,
          ),
      ),
    );
  }

  Future<void> _editFrame(
    SceneNode node,
    int trackIndex,
    int frameIndex,
  ) async {
    final track = node.tracks[trackIndex];
    final result = await showOverlay<({SceneKeyframe? frame})>(
      context,
      const DialogConfiguration(),
      builder: (_) => _KeyframeDialog(track: track, index: frameIndex),
    ).future;
    if (!mounted || result == null) return;
    final frames = [...track.keyframes];
    if (result.frame case final frame?) {
      frames[frameIndex] = frame;
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
    widget.editor.updateNode(node.copyWith(tracks: tracks));
  }

  Widget _row(
    String label,
    Widget child, {
    bool selected = false,
    VoidCallback? onSelect,
  }) => SizedBox(
    height: 28,
    child: Row(
      children: [
        SizedBox(
          width: studioTimelineLabelWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: selected
                  ? Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).small().semiBold()
                  : Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).small().muted(),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final node = editor.selectedNode;
    final hasTrack = node.tracks.any((track) => track.property == _property);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Match Slider's internal inset, with room for endpoint keyframe targets.
    final trackInset =
        studioTimelineTrackPadding + theme.density.baseGap * theme.scaling / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 136,
              child: StudioEnumSelect(
                value: _property,
                values: SceneMotionProperty.values,
                onChanged: (value) => setState(() => _property = value),
              ),
            ),
            OutlineButton(
              key: const ValueKey('timeline-add-track'),
              density: ButtonDensity.dense,
              onPressed: hasTrack ? null : _addTrack,
              child: const Text('Add track').small(),
            ),
            OutlineButton(
              key: const ValueKey('timeline-add-keyframe'),
              density: ButtonDensity.dense,
              onPressed: hasTrack ? _addKeyframe : null,
              child: const Text('+ Keyframe').small(),
            ),
            if (hasTrack)
              GhostButton(
                density: ButtonDensity.dense,
                onPressed: () => editor.updateNode(
                  node.copyWith(
                    tracks: node.tracks
                        .where((track) => track.property != _property)
                        .toList(),
                  ),
                ),
                child: const Text('Remove track').small(),
              ),
          ],
        ),
        const Gap(6),
        SizedBox(
          height: 152,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(
                1.0,
                constraints.maxWidth - studioTimelineLabelWidth - 2 * trackInset,
              );
              final total = math.max(1, widget.duration.inMilliseconds);
              final progress =
                  (widget.elapsed.inMicroseconds /
                          math.max(1, widget.duration.inMicroseconds))
                      .clamp(0.0, 1.0);
              return Stack(
                children: [
                  Column(
                    children: [
                      SizedBox(
                        height: 18,
                        child: Row(
                          children: [
                            SizedBox(
                              width: studioTimelineLabelWidth,
                              child: const Text('Layer').xSmall().muted(),
                            ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: trackInset,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('0s').xSmall().muted(),
                                    Text(
                                      '${(total / 2000).toStringAsFixed(2)}s',
                                    ).xSmall().muted(),
                                    Text(
                                      '${(total / 1000).toStringAsFixed(2)}s',
                                    ).xSmall().muted(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final item
                                in editor.previewDocument.layerOrder) ...[
                              _row(
                                item.id,
                                selected: editor.selectedIds.contains(item.id),
                                Stack(
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    Positioned.fill(
                                      left: trackInset,
                                      right: trackInset,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: colors.muted.withValues(
                                            alpha: .35,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left:
                                          trackInset +
                                          item.motionTiming.delayMs /
                                          total *
                                          width,
                                      width: math.max(
                                        8,
                                        (getSceneMotionDuration(
                                                  item,
                                                  widget.fallbackDuration,
                                                ).inMilliseconds -
                                                item.motionTiming.delayMs) /
                                            total *
                                            width,
                                      ),
                                      top: 4,
                                      bottom: 4,
                                      child: GestureDetector(
                                        key: ValueKey(
                                          'timeline-block-${item.id}',
                                        ),
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => editor.selectNode(item.id),
                                        dragStartBehavior:
                                            DragStartBehavior.down,
                                        onHorizontalDragStart: (details) =>
                                            _start(item, details, width),
                              onHorizontalDragUpdate: (details) {
                                final source = _source;
                                if (source == null) return;
                                _preview(
                                  source.copyWith(
                                    motionTiming: SceneMotionTiming(
                                      delayMs:
                                          (source.motionTiming.delayMs +
                                                  _delta(details))
                                              .clamp(0, 60000),
                                      durationMs:
                                          source.motionTiming.durationMs,
                                      curve: source.motionTiming.curve,
                                    ),
                                  ),
                                );
                              },
                              onHorizontalDragEnd: (_) => _commit(),
                              onHorizontalDragCancel: _cancel,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.primary.withValues(
                                      alpha: .55,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: GestureDetector(
                                      key: ValueKey(
                                        'timeline-resize-${item.id}',
                                      ),
                                      behavior: HitTestBehavior.opaque,
                                      dragStartBehavior: DragStartBehavior.down,
                                      onHorizontalDragStart: (details) =>
                                          _start(item, details, width),
                                      onHorizontalDragUpdate: (details) {
                                        final source = _source;
                                        if (source == null) return;
                                        final span =
                                            getSceneMotionDuration(
                                              source,
                                              widget.fallbackDuration,
                                            ).inMilliseconds -
                                            source.motionTiming.delayMs;
                                        final minimum = source.tracks.fold<int>(
                                          1,
                                          (value, track) => math.max(
                                            value,
                                            track.keyframes.length - 1,
                                          ),
                                        );
                                        final duration =
                                            (span + _delta(details)).clamp(
                                              minimum,
                                              60000,
                                            );
                                        _preview(
                                          source.copyWith(
                                            tracks: [
                                              for (final track in source.tracks)
                                                (() {
                                                  var previous = -1;
                                                  final frames =
                                                      <SceneKeyframe>[];
                                                  for (
                                                    var i = 0;
                                                    i < track.keyframes.length;
                                                    i++
                                                  ) {
                                                    final frame =
                                                        track.keyframes[i];
                                                    final time =
                                                        (span == 0
                                                                ? 0
                                                                : (frame.timeMs *
                                                                          duration /
                                                                          span)
                                                                      .round())
                                                            .clamp(
                                                              previous + 1,
                                                              duration -
                                                                  (track
                                                                          .keyframes
                                                                          .length -
                                                                      1 -
                                                                      i),
                                                            );
                                                    frames.add(
                                                      SceneKeyframe(
                                                        timeMs: time,
                                                        value: frame.value,
                                                        curve: frame.curve,
                                                      ),
                                                    );
                                                    previous = time;
                                                  }
                                                  return SceneMotionTrack(
                                                    property: track.property,
                                                    keyframes: frames,
                                                  );
                                                })(),
                                            ],
                                            motionTiming: SceneMotionTiming(
                                              durationMs: duration,
                                              delayMs:
                                                  source.motionTiming.delayMs,
                                              curve: source.motionTiming.curve,
                                            ),
                                          ),
                                        );
                                      },
                                      onHorizontalDragEnd: (_) => _commit(),
                                      onHorizontalDragCancel: _cancel,
                                      child: const SizedBox(
                                        width: 12,
                                        child: Center(
                                          child: Icon(
                                            LucideIcons.gripVertical,
                                            size: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        onSelect: () => editor.selectNode(item.id),
                      ),
                      for (
                        var trackIndex = 0;
                        trackIndex < item.tracks.length;
                        trackIndex++
                      )
                        _row(
                          '  ${item.tracks[trackIndex].property.name}',
                          Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              Positioned.fill(
                                left: trackInset,
                                right: trackInset,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.muted.withValues(alpha: .18),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                              for (
                                var frameIndex = 0;
                                frameIndex <
                                    item.tracks[trackIndex].keyframes.length;
                                frameIndex++
                              )
                                Positioned(
                                  left:
                                      trackInset +
                                      (item.motionTiming.delayMs +
                                          item
                                              .tracks[trackIndex]
                                              .keyframes[frameIndex]
                                              .timeMs) /
                                      total *
                                      width -
                                      studioTimelineTrackPadding,
                                  top: 2,
                                  child: GestureDetector(
                                    key: ValueKey(
                                      'keyframe-${item.id}-$trackIndex-$frameIndex',
                                    ),
                                    onTap: () {
                                      editor.selectNode(item.id);
                                      setState(
                                        () => _property =
                                            item.tracks[trackIndex].property,
                                      );
                                    },
                                    onDoubleTap: () =>
                                        _editFrame(item, trackIndex, frameIndex),
                                    dragStartBehavior: DragStartBehavior.down,
                                    onHorizontalDragStart: (details) =>
                                        _start(item, details, width),
                                    onHorizontalDragUpdate: (details) {
                                      final source = _source;
                                      if (source == null) return;
                                      final track = source.tracks[trackIndex];
                                      final frame = track.keyframes[frameIndex];
                                      final min = frameIndex == 0
                                          ? 0
                                          : track
                                                    .keyframes[frameIndex - 1]
                                                    .timeMs +
                                                1;
                                      final max =
                                          frameIndex ==
                                              track.keyframes.length - 1
                                          ? 60000
                                          : track
                                                    .keyframes[frameIndex + 1]
                                                    .timeMs -
                                                1;
                                      final frames = [...track.keyframes]
                                        ..[frameIndex] = SceneKeyframe(
                                          timeMs:
                                              (frame.timeMs + _delta(details))
                                                  .clamp(min, max),
                                          value: frame.value,
                                          curve: frame.curve,
                                        );
                                      _preview(
                                        source.copyWith(
                                          tracks: [...source.tracks]
                                            ..[trackIndex] = SceneMotionTrack(
                                              property: track.property,
                                              keyframes: frames,
                                            ),
                                        ),
                                      );
                                    },
                                    onHorizontalDragEnd: (_) => _commit(),
                                    onHorizontalDragCancel: _cancel,
                                    child: Tooltip(
                                      tooltip: (_) => const Text(
                                        'Drag time · Double-click to edit',
                                      ),
                                      child: const SizedBox(
                                        width: 2 * studioTimelineTrackPadding,
                                        height: 24,
                                        child: Icon(
                                          LucideIcons.diamond,
                                          size: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          onSelect: () {
                            editor.selectNode(item.id);
                            setState(
                              () =>
                                  _property = item.tracks[trackIndex].property,
                            );
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left:
                studioTimelineLabelWidth + trackInset + progress * width - 3,
            top: 15,
            bottom: 0,
            child: IgnorePointer(
              child: Column(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: colors.primary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  ),
),
      ],
    );
  }
}

class _KeyframeDialog extends StatefulWidget {
  const _KeyframeDialog({required this.track, required this.index});
  final SceneMotionTrack track;
  final int index;
  @override
  State<_KeyframeDialog> createState() => _KeyframeDialogState();
}

class _KeyframeDialogState extends State<_KeyframeDialog> {
  late final _time = TextEditingController(
    text: '${widget.track.keyframes[widget.index].timeMs}',
  );
  late final _value = TextEditingController(
    text: '${widget.track.keyframes[widget.index].value}',
  );
  late SceneKeyframeCurve _curve = widget.track.keyframes[widget.index].curve;
  String? _error;
  @override
  void dispose() {
    _time.dispose();
    _value.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final time = getIntegerInput('Time', _time.text);
      final value = getFiniteNumberInput('Value', _value.text);
      final frames = widget.track.keyframes;
      if (time < 0 ||
          time > 60000 ||
          (widget.index > 0 && time <= frames[widget.index - 1].timeMs) ||
          (widget.index < frames.length - 1 &&
              time >= frames[widget.index + 1].timeMs)) {
        throw const FormatException(
          'Time must stay between adjacent keyframes (0..60000 ms).',
        );
      }
      if (value.abs() > 100000 ||
          (widget.track.property == SceneMotionProperty.opacity &&
              (value < 0 || value > 1))) {
        throw const FormatException(
          'Opacity must be 0..1; other values must be within ±100000.',
        );
      }
      Navigator.of(
        context,
      ).pop((frame: SceneKeyframe(timeMs: time, value: value, curve: _curve)));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.track.property.name} keyframe'),
    content: SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          StudioFormField(
            label: 'Time ms',
            controller: _time,
            inputKey: const ValueKey('keyframe-time'),
          ),
          StudioFormField(
            label: 'Value',
            controller: _value,
            inputKey: const ValueKey('keyframe-value'),
          ),
          StudioEnumSelect(
            value: _curve,
            values: SceneKeyframeCurve.values,
            onChanged: (value) => setState(() => _curve = value),
          ),
          if (_error != null) Text(_error!).small(),
        ],
      ),
    ),
    actions: [
      GhostButton(
        onPressed: () => Navigator.of(context).pop((frame: null)),
        child: const Text('Delete'),
      ),
      OutlineButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      PrimaryButton(onPressed: _save, child: const Text('Apply')),
    ],
  );
}
