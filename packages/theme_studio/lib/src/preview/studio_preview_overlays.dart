import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/studio_components.dart';
import '../model/node_geometry.dart';
import '../model/studio_input.dart';

/// Selection belongs to the canvas, outside the component's paint transform.
/// Handles keep their screen size and remain usable on small or scaled nodes.
class PreviewSelectionOverlay extends StatelessWidget {
  const PreviewSelectionOverlay({
    required this.viewportScale,
    required this.geometry,
    required this.showHandles,
    required this.onStart,
    required this.onUpdate,
    required this.onStop,
    required this.onCancel,
    super.key,
  });

  final double viewportScale;
  final SceneNodeGeometry geometry;
  final bool showHandles;
  final void Function(NodeResizeHandle, DragStartDetails) onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final rect = Offset.zero & geometry.rect.size;
    final matrix = geometry.worldTransform;
    final points = calculateHandlePoints(rect: rect, matrix: matrix);
    final hitSize = 20 / viewportScale;
    final handleSize = 8 / viewportScale;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _SelectionPainter(points, 1.5 / viewportScale),
            ),
          ),
        ),
        if (showHandles && isInvertibleEditingPlane(matrix))
          for (final entry in points.entries)
            Positioned(
              left: entry.value.dx - hitSize / 2,
              top: entry.value.dy - hitSize / 2,
              width: hitSize,
              height: hitSize,
              child: MouseRegion(
                cursor: entry.key.cursor,
                child: Listener(
                  onPointerCancel: (_) => onCancel(),
                  child: GestureDetector(
                    key: ValueKey('resize-${entry.key.name}'),
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: (details) => onStart(entry.key, details),
                    onPanUpdate: onUpdate,
                    onPanEnd: onStop,
                    onPanCancel: onCancel,
                    child: Center(
                      child: Container(
                        width: handleSize,
                        height: handleSize,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xff8b5cf6),
                            width: 1 / viewportScale,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter(this.points, this.strokeWidth);

  final Map<NodeResizeHandle, Offset> points;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addPolygon([
        points[NodeResizeHandle.topLeft]!,
        points[NodeResizeHandle.topRight]!,
        points[NodeResizeHandle.bottomRight]!,
        points[NodeResizeHandle.bottomLeft]!,
      ], true);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff8b5cf6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      strokeWidth != oldDelegate.strokeWidth ||
      points.entries.any(
        (entry) => oldDelegate.points[entry.key] != entry.value,
      );
}

class PreviewGridPainter extends CustomPainter {
  const PreviewGridPainter(this.spacing);

  final int spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x507f7f7f)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(PreviewGridPainter oldDelegate) =>
      spacing != oldDelegate.spacing;
}

bool canShowResizeHandles(
  SceneDocument document,
  SceneNode selected,
  Set<String> selectedIds,
  StudioCanvasTool tool,
  bool readOnly,
) {
  if (readOnly || selectedIds.length != 1 || tool != StudioCanvasTool.move) {
    return false;
  }
  if (selected.parentId == null) return true;
  final parent = document.nodes.firstWhere(
    (node) => node.id == selected.parentId,
  );
  return parent.layout!.direction == SceneLayoutDirection.absolute;
}

class PreviewDropTargets extends StatelessWidget {
  const PreviewDropTargets({
    required this.canAccept,
    required this.onAcceptComponent,
    required this.onAcceptNode,
    required this.child,
    super.key,
  });

  final bool canAccept;
  final void Function(StudioComponent, Offset) onAcceptComponent;
  final void Function(SceneNode, Offset) onAcceptNode;
  final Widget child;

  @override
  Widget build(BuildContext context) => DragTarget<StudioComponent>(
    onWillAcceptWithDetails: (_) => canAccept,
    onAcceptWithDetails: (details) =>
        onAcceptComponent(details.data, details.offset),
    builder: (context, _, _) => DragTarget<SceneNode>(
      onWillAcceptWithDetails: (_) => canAccept,
      onAcceptWithDetails: (details) =>
          onAcceptNode(details.data, details.offset),
      builder: (context, _, _) => child,
    ),
  );
}

class PreviewMarqueeOverlay extends StatelessWidget {
  const PreviewMarqueeOverlay({required this.marqueeRect, super.key});

  final ValueNotifier<Rect?> marqueeRect;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Rect?>(
    valueListenable: marqueeRect,
    builder: (context, rect, _) {
      if (rect == null) return const SizedBox.shrink();
      return Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x208b5cf6),
              border: Border.all(color: const Color(0xff8b5cf6)),
            ),
          ),
        ),
      );
    },
  );
}

class PreviewInlineTextEditor extends StatelessWidget {
  const PreviewInlineTextEditor({
    required this.bounds,
    required this.controller,
    required this.focusNode,
    required this.onCommit,
    required this.onCancel,
    super.key,
  });

  final Rect bounds;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCommit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Positioned.fromRect(
    rect: bounds,
    child: Localizations.override(
      context: context,
      delegates: const [DefaultMaterialLocalizations.delegate],
      child: Material(
        color: Colors.transparent,
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              onCancel();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: const ValueKey('canvas-text-editor'),
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(color: Colors.white, fontSize: 24),
            onSubmitted: (_) => onCommit(),
            onTapOutside: (_) => onCommit(),
            decoration: const InputDecoration(
              filled: true,
              fillColor: Color(0xee18181b),
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ),
    ),
  );
}
