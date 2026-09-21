import 'package:flutter/material.dart';

/// A vertical pane divider that resizes the pane beside it.
///
/// The visible line stays thin while the hit area is wider, and the cursor
/// becomes a left/right resize arrow on hover.
class PaneDivider extends StatelessWidget {
  const PaneDivider({required this.onDrag, super.key});

  /// Called with the horizontal drag delta in logical pixels.
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: 8,
          child: Center(
            child: Container(
              width: 1,
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}
