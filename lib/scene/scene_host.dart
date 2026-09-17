import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

typedef SceneRegionBuilder<T> = Widget Function(BuildContext context, T slots);

/// Composes stable visual layers in their explicit spatial order.
class SceneHost extends StatelessWidget {
  const SceneHost({
    required this.background,
    required this.overlay,
    required this.content,
    super.key,
  });

  final Widget background;
  final Widget overlay;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [background, overlay, content],
    );
  }
}

/// Connects one typed slot to one visual region's build boundary.
class SceneRegion<T> extends StatelessWidget {
  const SceneRegion({
    required this.valueListenable,
    required this.builder,
    this.repaintBoundary = false,
    super.key,
  });

  final ValueListenable<T> valueListenable;
  final SceneRegionBuilder<T> builder;
  final bool repaintBoundary;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<T>(
      valueListenable: valueListenable,
      builder: (context, slots, child) {
        final region = builder(context, slots);
        return repaintBoundary ? RepaintBoundary(child: region) : region;
      },
    );
  }
}
