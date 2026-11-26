import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../ui/studio_form.dart';
import '../ui/studio_tooltip.dart';

const studioTimelineLabelWidth = 120.0;
const studioTimelineTrackPadding = 10.0;

class TimelineTrackToolbar extends StatelessWidget {
  const TimelineTrackToolbar({
    required this.property,
    required this.readOnly,
    required this.hasSelection,
    required this.hasTrack,
    required this.onPropertyChanged,
    required this.onAddTrack,
    required this.onAddKeyframe,
    required this.onRemoveTrack,
    super.key,
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

class TimelineScaleHeader extends StatelessWidget {
  const TimelineScaleHeader({
    required this.trackInset,
    required this.totalMs,
    super.key,
  });

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

class TimelineRow extends StatelessWidget {
  const TimelineRow({
    required this.label,
    required this.selected,
    required this.trackInset,
    required this.laneColor,
    required this.onSelect,
    required this.overlays,
    super.key,
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

class TimelineLayerDurationBlock extends StatelessWidget {
  const TimelineLayerDurationBlock({
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
    super.key,
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

class TimelinePropertyTrackRow extends StatelessWidget {
  const TimelinePropertyTrackRow({
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
    super.key,
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
  Widget build(BuildContext context) => TimelineRow(
    label: '  ${track.property.name}',
    selected: false,
    trackInset: trackInset,
    laneColor: laneColor,
    onSelect: onSelect,
    overlays: [
      for (final (frameIndex, frame) in track.keyframes.indexed)
        TimelineKeyframeMarker(
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

class TimelineKeyframeMarker extends StatelessWidget {
  const TimelineKeyframeMarker({
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
    super.key,
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

class TimelinePlayhead extends StatelessWidget {
  const TimelinePlayhead({required this.left, required this.color, super.key});

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
