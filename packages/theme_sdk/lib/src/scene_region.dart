import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:scene/scene.dart';

typedef SceneRegionBuilder<T> = Widget Function(BuildContext context, T slots);

/// Connects one typed slot to one visual region's build boundary.
class SceneRegion<T> extends StatelessWidget {
  const SceneRegion({
    required this.valueListenable,
    required this.builder,
    super.key,
  });

  final ValueListenable<T> valueListenable;
  final SceneRegionBuilder<T> builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<T>(
      valueListenable: valueListenable,
      builder: (context, slots, _) => builder(context, slots),
    );
  }
}

/// Scales fixed-pixel typography, icons, and padding proportionally to the
/// authored [node] rectangle on [canvas].
class ScaledNodeRegion extends StatelessWidget {
  const ScaledNodeRegion({
    required this.node,
    required this.canvas,
    required this.child,
    this.scale = 1,
    super.key,
  });

  final SceneNode node;
  final SceneCanvas canvas;
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      child: SizedBox(
        width: node.rect.width * canvas.referenceWidth / scale,
        height: node.rect.height * canvas.referenceHeight / scale,
        child: child,
      ),
    );
  }
}
