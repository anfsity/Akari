import 'package:flutter/material.dart';

/// A pane divider that resizes the pane beside it.
///
/// [dragAxis] is the direction the divider moves. The visible line stays thin
/// while the hit area is wider, and the cursor becomes a resize arrow on hover.
class PaneDivider extends StatelessWidget {
  const PaneDivider({required this.dragAxis, required this.onDrag, super.key});

  final Axis dragAxis;

  /// Called with the drag delta along [dragAxis] in logical pixels.
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).dividerColor;
    if (dragAxis == Axis.horizontal) {
      return MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
          child: SizedBox(
            width: 8,
            child: Center(child: Container(width: 1, color: color)),
          ),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        child: SizedBox(
          height: 8,
          child: Center(child: Container(height: 1, color: color)),
        ),
      ),
    );
  }
}
