import 'package:flutter/material.dart';

/// A pane divider that resizes the pane beside it.
///
/// [dragAxis] is the direction the divider moves. The visible line stays thin
/// while the hit area is wider, and the cursor becomes a resize arrow on hover.
/// Hovering thickens the line so the divider is easy to find.
class PaneDivider extends StatefulWidget {
  const PaneDivider({required this.dragAxis, required this.onDrag, super.key});

  final Axis dragAxis;

  /// Called with the drag delta along [dragAxis] in logical pixels.
  final ValueChanged<double> onDrag;

  @override
  State<PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<PaneDivider> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _hovered ? scheme.primary : Theme.of(context).dividerColor;
    final thickness = _hovered ? 2.0 : 1.0;
    if (widget.dragAxis == Axis.horizontal) {
      return MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
          child: SizedBox(
            width: 8,
            child: Center(child: Container(width: thickness, color: color)),
          ),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => widget.onDrag(details.delta.dy),
        child: SizedBox(
          height: 8,
          child: Center(child: Container(height: thickness, color: color)),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (value == _hovered) {
      return;
    }
    setState(() => _hovered = value);
  }
}
