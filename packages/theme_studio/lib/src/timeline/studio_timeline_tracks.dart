import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import 'studio_keyframe_dialog.dart';
import 'studio_timeline_rows.dart';
import 'studio_timeline_track_math.dart';

export 'studio_timeline_rows.dart'
    show studioTimelineLabelWidth, studioTimelineTrackPadding;

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
    final updated = addDefaultTimelineTrack(node, _property);
    if (!identical(updated, node)) {
      editor.updateNode(updated);
    }
  }

  void _addKeyframe() {
    final editor = widget.editor;
    if (widget.readOnly ||
        editor.selectedIds.isEmpty ||
        !editor.tryApplyDraft()) {
      return;
    }
    final node = editor.selectedNode;
    final updated = insertTimelineKeyframe(node, _property, widget.elapsed);
    if (!identical(updated, node)) {
      editor.updateNode(updated);
    }
  }

  Future<void> _editFrame(
    String nodeId,
    SceneMotionProperty property,
    int frameIndex,
  ) async {
    final editor = widget.editor;
    if (widget.readOnly || !editor.tryApplyDraft()) return;
    final initial = findTimelineTrackTarget(
      editor.document,
      nodeId,
      property,
      frameIndex,
    );
    if (initial == null) return;
    final result = await showOverlay<({SceneKeyframe? frame})>(
      context,
      const DialogConfiguration(),
      builder: (_) =>
          StudioKeyframeDialog(track: initial.track, index: frameIndex),
    ).future;
    if (!mounted || result == null || !identical(editor, widget.editor)) {
      return;
    }
    final latest = findTimelineTrackTarget(
      editor.document,
      nodeId,
      property,
      frameIndex,
    );
    if (latest == null || latest.track != initial.track) return;
    editor.updateNode(
      replaceOrRemoveTimelineKeyframe(
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
    _preview(shiftTimelineNodeDelay(source, _delta(details)));
  }

  void _dragDuration(DragUpdateDetails details) {
    final source = _source;
    if (source == null) return;
    _preview(
      resizeTimelineNodeDuration(
        source,
        widget.fallbackDuration,
        _delta(details),
      ),
    );
  }

  void _dragKeyframe(
    DragUpdateDetails details,
    int trackIndex,
    int frameIndex,
  ) {
    final source = _source;
    if (source == null) return;
    _preview(
      retimeTimelineKeyframe(source, trackIndex, frameIndex, _delta(details)),
    );
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
        TimelineTrackToolbar(
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
                      TimelineScaleHeader(
                        trackInset: trackInset,
                        totalMs: total,
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final item
                                in editor.previewDocument.layerOrder) ...[
                              TimelineRow(
                                label: item.id,
                                selected: editor.selectedIds.contains(item.id),
                                trackInset: trackInset,
                                laneColor: colors.muted.withValues(alpha: .35),
                                onSelect: () => editor.selectNode(item.id),
                                overlays: [
                                  TimelineLayerDurationBlock(
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
                                TimelinePropertyTrackRow(
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
                  TimelinePlayhead(
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
