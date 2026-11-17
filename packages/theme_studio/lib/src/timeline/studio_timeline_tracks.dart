import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../ui/studio_form.dart';
import '../ui/studio_form_values.dart';
import '../ui/studio_tooltip.dart';

const studioTimelineLabelWidth = 120.0;
const studioTimelineTrackPadding = 10.0;

/// Track gestures preview against a captured node and commit once on release.
class StudioTimelineTracks extends StatefulWidget {
  const StudioTimelineTracks({
    required this.editor,
    required this.duration,
    required this.elapsed,
    required this.fallbackDuration,
    this.readOnly = false,
    super.key,
  });
  final SceneEditor editor;
  final Duration duration;
  final Duration elapsed;
  final Duration fallbackDuration;
  final bool readOnly;
  @override
  State<StudioTimelineTracks> createState() => _StudioTimelineTracksState();
}

class _StudioTimelineTracksState extends State<StudioTimelineTracks> {
  SceneMotionProperty _property = SceneMotionProperty.opacity;
  SceneNode? _source;
  SceneNode? _candidate;
  double _origin = 0;
  double _millisecondsPerPixel = 1;

  @override
  void didUpdateWidget(StudioTimelineTracks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.editor != widget.editor || widget.readOnly) &&
        (_source != null || _candidate != null)) {
      final previous = oldWidget.editor;
      _source = _candidate = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!previous.isDisposed) previous.cancelPreview();
      });
    }
  }

  @override
  void dispose() {
    if (_source != null || _candidate != null) {
      final editor = widget.editor;
      _source = _candidate = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!editor.isDisposed) editor.cancelPreview();
      });
    }
    super.dispose();
  }

  void _start(SceneNode node, DragStartDetails details, double width) {
    if (widget.readOnly || !widget.editor.tryApplyDraft()) return;
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
    if (widget.readOnly ||
        editor.selectedIds.isEmpty ||
        !editor.tryApplyDraft()) {
      return;
    }
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
    if (widget.readOnly ||
        editor.selectedIds.isEmpty ||
        !editor.tryApplyDraft()) {
      return;
    }
    final node = editor.selectedNode;
    final index = node.tracks.indexWhere(
      (track) => track.property == _property,
    );
    if (index < 0) return;
    final track = node.tracks[index];
    final time = (widget.elapsed.inMilliseconds - node.motionTiming.delayMs)
        .clamp(0, maxSceneMotionTimeMs);
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
    String nodeId,
    SceneMotionProperty property,
    int frameIndex,
  ) async {
    final editor = widget.editor;
    if (widget.readOnly || !editor.tryApplyDraft()) return;
    final initial = _findTrackTarget(
      editor.document,
      nodeId,
      property,
      frameIndex,
    );
    if (initial == null) return;
    final result = await showOverlay<({SceneKeyframe? frame})>(
      context,
      const DialogConfiguration(),
      builder: (_) => _KeyframeDialog(track: initial.track, index: frameIndex),
    ).future;
    if (!mounted || result == null || !identical(editor, widget.editor)) {
      return;
    }
    final latest = _findTrackTarget(
      editor.document,
      nodeId,
      property,
      frameIndex,
    );
    if (latest == null || latest.track != initial.track) return;
    editor.updateNode(
      _replaceOrRemoveKeyframe(
        latest.node,
        latest.trackIndex,
        frameIndex,
        result.frame,
      ),
    );
  }

  void _removeTrack() {
    final editor = widget.editor;
    if (widget.readOnly ||
        editor.selectedIds.isEmpty ||
        !editor.tryApplyDraft()) {
      return;
    }
    final current = editor.selectedNode;
    editor.updateNode(
      current.copyWith(
        tracks: current.tracks
            .where((track) => track.property != _property)
            .toList(),
      ),
    );
  }

  void _selectTrack(String nodeId, SceneMotionProperty property) {
    widget.editor.selectNode(nodeId);
    setState(() => _property = property);
  }

  void _dragDelay(DragUpdateDetails details) {
    final source = _source;
    if (source == null) return;
    _preview(_shiftNodeDelay(source, _delta(details)));
  }

  void _dragDuration(DragUpdateDetails details) {
    final source = _source;
    if (source == null) return;
    _preview(
      _resizeNodeDuration(source, widget.fallbackDuration, _delta(details)),
    );
  }

  void _dragKeyframe(
    DragUpdateDetails details,
    int trackIndex,
    int frameIndex,
  ) {
    final source = _source;
    if (source == null) return;
    _preview(_retimeKeyframe(source, trackIndex, frameIndex, _delta(details)));
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final hasSelection = editor.selectedIds.isNotEmpty;
    final node = hasSelection ? editor.selectedNode : null;
    final hasTrack =
        node != null && node.tracks.any((track) => track.property == _property);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Match Slider's internal inset, with room for endpoint keyframe targets.
    final trackInset =
        studioTimelineTrackPadding + theme.density.baseGap * theme.scaling / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(6),
        _TrackToolbar(
          property: _property,
          readOnly: widget.readOnly,
          hasSelection: hasSelection,
          hasTrack: hasTrack,
          onPropertyChanged: (value) => setState(() => _property = value),
          onAddTrack: _addTrack,
          onAddKeyframe: _addKeyframe,
          onRemoveTrack: _removeTrack,
        ),
        const Gap(6),
        SizedBox(
          height: 152,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(
                1.0,
                constraints.maxWidth -
                    studioTimelineLabelWidth -
                    2 * trackInset,
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
                      _TimelineScaleHeader(
                        trackInset: trackInset,
                        totalMs: total,
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final item
                                in editor.previewDocument.layerOrder) ...[
                              _TimelineRow(
                                label: item.id,
                                selected: editor.selectedIds.contains(item.id),
                                trackInset: trackInset,
                                laneColor: colors.muted.withValues(alpha: .35),
                                onSelect: () => editor.selectNode(item.id),
                                overlays: [
                                  _LayerDurationBlock(
                                    node: item,
                                    totalMs: total,
                                    width: width,
                                    trackInset: trackInset,
                                    fallbackDuration: widget.fallbackDuration,
                                    color: colors.primary.withValues(
                                      alpha: .55,
                                    ),
                                    onSelect: () => editor.selectNode(item.id),
                                    onStartDrag: (details) =>
                                        _start(item, details, width),
                                    onDragDelay: _dragDelay,
                                    onDragDuration: _dragDuration,
                                    onStopDrag: _commit,
                                    onCancelDrag: _cancel,
                                  ),
                                ],
                              ),
                              for (final (trackIndex, track)
                                  in item.tracks.indexed)
                                _PropertyTrackRow(
                                  nodeId: item.id,
                                  delayMs: item.motionTiming.delayMs,
                                  trackIndex: trackIndex,
                                  track: track,
                                  totalMs: total,
                                  width: width,
                                  trackInset: trackInset,
                                  laneColor: colors.muted.withValues(
                                    alpha: .18,
                                  ),
                                  onSelect: () =>
                                      _selectTrack(item.id, track.property),
                                  onEditFrame: (frameIndex) => _editFrame(
                                    item.id,
                                    track.property,
                                    frameIndex,
                                  ),
                                  onStartDrag: (details) =>
                                      _start(item, details, width),
                                  onDragKeyframe: (details, frameIndex) =>
                                      _dragKeyframe(
                                        details,
                                        trackIndex,
                                        frameIndex,
                                      ),
                                  onStopDrag: _commit,
                                  onCancelDrag: _cancel,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  _TimelinePlayhead(
                    left:
                        studioTimelineLabelWidth +
                        trackInset +
                        progress * width -
                        3,
                    color: colors.primary,
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

SceneNode _shiftNodeDelay(SceneNode source, int deltaMs) => source.copyWith(
  motionTiming: SceneMotionTiming(
    delayMs: (source.motionTiming.delayMs + deltaMs).clamp(
      0,
      maxSceneMotionTimeMs,
    ),
    durationMs: source.motionTiming.durationMs,
    curve: source.motionTiming.curve,
  ),
);

SceneNode _resizeNodeDuration(
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

SceneNode _retimeKeyframe(
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

({SceneNode node, int trackIndex, SceneMotionTrack track})? _findTrackTarget(
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

SceneNode _replaceOrRemoveKeyframe(
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

class _TrackToolbar extends StatelessWidget {
  const _TrackToolbar({
    required this.property,
    required this.readOnly,
    required this.hasSelection,
    required this.hasTrack,
    required this.onPropertyChanged,
    required this.onAddTrack,
    required this.onAddKeyframe,
    required this.onRemoveTrack,
  });

  final SceneMotionProperty property;
  final bool readOnly;
  final bool hasSelection;
  final bool hasTrack;
  final ValueChanged<SceneMotionProperty> onPropertyChanged;
  final VoidCallback onAddTrack;
  final VoidCallback onAddKeyframe;
  final VoidCallback onRemoveTrack;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 136,
        child: StudioEnumSelect(
          value: property,
          values: SceneMotionProperty.values,
          onChanged: onPropertyChanged,
        ),
      ),
      OutlineButton(
        key: const ValueKey('timeline-add-track'),
        density: ButtonDensity.dense,
        onPressed: readOnly || !hasSelection || hasTrack ? null : onAddTrack,
        child: const Text('Add track').small(),
      ),
      OutlineButton(
        key: const ValueKey('timeline-add-keyframe'),
        density: ButtonDensity.dense,
        onPressed: !readOnly && hasTrack ? onAddKeyframe : null,
        child: const Text('+ Keyframe').small(),
      ),
      if (hasTrack)
        GhostButton(
          density: ButtonDensity.dense,
          onPressed: readOnly ? null : onRemoveTrack,
          child: const Text('Remove track').small(),
        ),
    ],
  );
}

class _TimelineScaleHeader extends StatelessWidget {
  const _TimelineScaleHeader({required this.trackInset, required this.totalMs});

  final double trackInset;
  final int totalMs;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 18,
    child: Row(
      children: [
        SizedBox(
          width: studioTimelineLabelWidth,
          child: const Text('Layer').xSmall().muted(),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: trackInset),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('0s').xSmall().muted(),
                Text('${(totalMs / 2000).toStringAsFixed(2)}s')
                    .xSmall()
                    .muted(),
                Text('${(totalMs / 1000).toStringAsFixed(2)}s')
                    .xSmall()
                    .muted(),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.label,
    required this.selected,
    required this.trackInset,
    required this.laneColor,
    required this.onSelect,
    required this.overlays,
  });

  final String label;
  final bool selected;
  final double trackInset;
  final Color laneColor;
  final VoidCallback onSelect;
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) => SizedBox(
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
        Expanded(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                left: trackInset,
                right: trackInset,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: laneColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              ...overlays,
            ],
          ),
        ),
      ],
    ),
  );
}

class _LayerDurationBlock extends StatelessWidget {
  const _LayerDurationBlock({
    required this.node,
    required this.totalMs,
    required this.width,
    required this.trackInset,
    required this.fallbackDuration,
    required this.color,
    required this.onSelect,
    required this.onStartDrag,
    required this.onDragDelay,
    required this.onDragDuration,
    required this.onStopDrag,
    required this.onCancelDrag,
  });

  final SceneNode node;
  final int totalMs;
  final double width;
  final double trackInset;
  final Duration fallbackDuration;
  final Color color;
  final VoidCallback onSelect;
  final GestureDragStartCallback onStartDrag;
  final GestureDragUpdateCallback onDragDelay;
  final GestureDragUpdateCallback onDragDuration;
  final VoidCallback onStopDrag;
  final VoidCallback onCancelDrag;

  @override
  Widget build(BuildContext context) {
    final spanMs =
        getSceneMotionDuration(node, fallbackDuration).inMilliseconds -
        node.motionTiming.delayMs;
    return Positioned(
      left: trackInset + node.motionTiming.delayMs / totalMs * width,
      width: math.max(8, spanMs / totalMs * width),
      top: 4,
      bottom: 4,
      child: Listener(
        onPointerCancel: (_) => onCancelDrag(),
        child: GestureDetector(
          key: ValueKey('timeline-block-${node.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: onStartDrag,
          onHorizontalDragUpdate: onDragDelay,
          onHorizontalDragEnd: (_) => onStopDrag(),
          onHorizontalDragCancel: onCancelDrag,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                key: ValueKey('timeline-resize-${node.id}'),
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onHorizontalDragStart: onStartDrag,
                onHorizontalDragUpdate: onDragDuration,
                onHorizontalDragEnd: (_) => onStopDrag(),
                onHorizontalDragCancel: onCancelDrag,
                child: const SizedBox(
                  width: 12,
                  child: Center(
                    child: Icon(LucideIcons.gripVertical, size: 12),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PropertyTrackRow extends StatelessWidget {
  const _PropertyTrackRow({
    required this.nodeId,
    required this.delayMs,
    required this.trackIndex,
    required this.track,
    required this.totalMs,
    required this.width,
    required this.trackInset,
    required this.laneColor,
    required this.onSelect,
    required this.onEditFrame,
    required this.onStartDrag,
    required this.onDragKeyframe,
    required this.onStopDrag,
    required this.onCancelDrag,
  });

  final String nodeId;
  final int delayMs;
  final int trackIndex;
  final SceneMotionTrack track;
  final int totalMs;
  final double width;
  final double trackInset;
  final Color laneColor;
  final VoidCallback onSelect;
  final ValueChanged<int> onEditFrame;
  final GestureDragStartCallback onStartDrag;
  final void Function(DragUpdateDetails details, int frameIndex) onDragKeyframe;
  final VoidCallback onStopDrag;
  final VoidCallback onCancelDrag;

  @override
  Widget build(BuildContext context) => _TimelineRow(
    label: '  ${track.property.name}',
    selected: false,
    trackInset: trackInset,
    laneColor: laneColor,
    onSelect: onSelect,
    overlays: [
      for (final (frameIndex, frame) in track.keyframes.indexed)
        _KeyframeMarker(
          nodeId: nodeId,
          trackIndex: trackIndex,
          frameIndex: frameIndex,
          timeMs: delayMs + frame.timeMs,
          totalMs: totalMs,
          width: width,
          trackInset: trackInset,
          onTap: onSelect,
          onDoubleTap: () => onEditFrame(frameIndex),
          onStartDrag: onStartDrag,
          onUpdateDrag: (details) => onDragKeyframe(details, frameIndex),
          onStopDrag: onStopDrag,
          onCancelDrag: onCancelDrag,
        ),
    ],
  );
}

class _KeyframeMarker extends StatelessWidget {
  const _KeyframeMarker({
    required this.nodeId,
    required this.trackIndex,
    required this.frameIndex,
    required this.timeMs,
    required this.totalMs,
    required this.width,
    required this.trackInset,
    required this.onTap,
    required this.onDoubleTap,
    required this.onStartDrag,
    required this.onUpdateDrag,
    required this.onStopDrag,
    required this.onCancelDrag,
  });

  final String nodeId;
  final int trackIndex;
  final int frameIndex;
  final int timeMs;
  final int totalMs;
  final double width;
  final double trackInset;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final GestureDragStartCallback onStartDrag;
  final GestureDragUpdateCallback onUpdateDrag;
  final VoidCallback onStopDrag;
  final VoidCallback onCancelDrag;

  @override
  Widget build(BuildContext context) => Positioned(
    left: trackInset + timeMs / totalMs * width - studioTimelineTrackPadding,
    top: 2,
    child: Listener(
      onPointerCancel: (_) => onCancelDrag(),
      child: GestureDetector(
        key: ValueKey('keyframe-$nodeId-$trackIndex-$frameIndex'),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: onStartDrag,
        onHorizontalDragUpdate: onUpdateDrag,
        onHorizontalDragEnd: (_) => onStopDrag(),
        onHorizontalDragCancel: onCancelDrag,
        child: StudioTooltip(
          tooltip: (_) => const Text('Drag time · Double-click to edit'),
          child: const SizedBox(
            width: 2 * studioTimelineTrackPadding,
            height: 24,
            child: Icon(LucideIcons.diamond, size: 13),
          ),
        ),
      ),
    ),
  );
}

class _TimelinePlayhead extends StatelessWidget {
  const _TimelinePlayhead({required this.left, required this.color});

  final double left;
  final Color color;

  @override
  Widget build(BuildContext context) => Positioned(
    left: left,
    top: 15,
    bottom: 0,
    child: IgnorePointer(
      child: Column(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Container(width: 1.5, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    ),
  );
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
          time > maxSceneMotionTimeMs ||
          (widget.index > 0 && time <= frames[widget.index - 1].timeMs) ||
          (widget.index < frames.length - 1 &&
              time >= frames[widget.index + 1].timeMs)) {
        throw const FormatException(
          'Time must stay between adjacent keyframes (0..$maxSceneMotionTimeMs ms).',
        );
      }
      if (clampSceneKeyframeValue(widget.track.property, value) != value) {
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
          if (_error != null) StudioFormError(_error!),
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
