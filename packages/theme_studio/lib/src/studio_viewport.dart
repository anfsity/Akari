import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Owns the editor camera independently of scene geometry. Zooming keeps the
/// point under the pointer stationary; wheel panning and the hand tool never
/// become document edits. The child always lays out at reference resolution.
class StudioViewport extends StatefulWidget {
  const StudioViewport({
    required this.canvasKey,
    required this.referenceSize,
    required this.zoom,
    required this.resetView,
    required this.panEnabled,
    required this.onZoom,
    required this.childBuilder,
    super.key,
  });

  final Key canvasKey;
  final Size referenceSize;
  final double? zoom;
  final int resetView;
  final bool panEnabled;
  final ValueChanged<double> onZoom;
  final Widget Function(double scale) childBuilder;

  @override
  State<StudioViewport> createState() => _StudioViewportState();
}

class _StudioViewportState extends State<StudioViewport> {
  Offset _pan = Offset.zero;
  double? _scale;
  Size? _viewportSize;
  Offset? _zoomAnchor;

  @override
  void didUpdateWidget(StudioViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetView != oldWidget.resetView ||
        widget.referenceSize != oldWidget.referenceSize) {
      _pan = Offset.zero;
      _scale = null;
      _zoomAnchor = null;
    }
  }

  Offset _calculateCenteredOrigin(Size viewport, double scale) => Offset(
    (viewport.width - widget.referenceSize.width * scale) / 2,
    (viewport.height - widget.referenceSize.height * scale) / 2,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = constraints.biggest;
      final scale =
          widget.zoom ??
          math.min(
            viewport.width / widget.referenceSize.width,
            viewport.height / widget.referenceSize.height,
          );
      if (_scale != null && _scale != scale) {
        final anchor = _zoomAnchor ?? viewport.center(Offset.zero);
        final scenePoint =
            (anchor -
                _calculateCenteredOrigin(_viewportSize!, _scale!) -
                _pan) /
            _scale!;
        _pan =
            anchor -
            _calculateCenteredOrigin(viewport, scale) -
            scenePoint * scale;
      }
      _scale = scale;
      _viewportSize = viewport;
      _zoomAnchor = null;
      final origin = _calculateCenteredOrigin(viewport, scale) + _pan;
      return ClipRect(
        child: Listener(
          key: const ValueKey('studio-viewport'),
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent) return;
            GestureBinding.instance.pointerSignalResolver.register(event, (_) {
              if (HardwareKeyboard.instance.isControlPressed) {
                _zoomAnchor = event.localPosition;
                widget.onZoom(
                  (scale * math.exp(-event.scrollDelta.dy / 400)).clamp(
                    0.05,
                    8.0,
                  ),
                );
              } else {
                setState(() => _pan -= event.scrollDelta);
              }
            });
          },
          child: MouseRegion(
            cursor: widget.panEnabled
                ? SystemMouseCursors.grab
                : MouseCursor.defer,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onPanUpdate: widget.panEnabled
                  ? (details) => setState(() => _pan += details.delta)
                  : null,
              child: IgnorePointer(
                ignoring: widget.panEnabled,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: widget.referenceSize.width,
                  maxWidth: widget.referenceSize.width,
                  minHeight: widget.referenceSize.height,
                  maxHeight: widget.referenceSize.height,
                  child: Transform(
                    alignment: Alignment.topLeft,
                    transform: Matrix4.identity()
                      ..translateByDouble(origin.dx, origin.dy, 0, 1)
                      ..scaleByDouble(scale, scale, 1, 1),
                    child: SizedBox.fromSize(
                      key: widget.canvasKey,
                      size: widget.referenceSize,
                      child: widget.childBuilder(scale),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
