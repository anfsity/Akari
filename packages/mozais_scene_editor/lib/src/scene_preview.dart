import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'editor_controller.dart';

const double _previewAspectRatio = 16 / 9;

/// Renders the document with the real runtime and overlays an editing box for
/// the selected node.
class ScenePreview extends StatelessWidget {
  const ScenePreview({required this.controller, super.key});

  final SceneEditorController controller;

  @override
  Widget build(BuildContext context) {
    final document = controller.document;
    if (document == null) {
      return const Center(child: Text('Open a scene to preview it.'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _fit(constraints.biggest);
        final selected = controller.selectedNode;
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SceneRuntime(
                    document: document,
                    theme: editorTheme(document),
                    nodeBuilder: buildPlaceholderNode,
                    activePredicates: controller.activePredicates,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                  ),
                ),
                if (selected != null)
                  _SelectionOverlay(
                    node: selected,
                    size: size,
                    onRectChanged: (rect) => controller.updateSelected(
                      (node) => node.copyWith(rect: rect),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Size _fit(Size available) {
  if (available.width <= 0 || available.height <= 0) {
    return const Size(160, 90);
  }
  final width = available.width;
  final height = width / _previewAspectRatio;
  if (height <= available.height) {
    return Size(width, height);
  }
  return Size(available.height * _previewAspectRatio, available.height);
}

/// Draws a labelled placeholder for a node so the editor preview shows layout
/// without depending on the greeter's widget catalog.
Widget buildPlaceholderNode(BuildContext context, SceneNode node) {
  final color = _kindColor(node.kind);
  return DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.22),
      border: Border.all(color: color.withValues(alpha: 0.9)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Text(
          node.id,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

Color _kindColor(SceneNodeKind kind) {
  final hue = (kind.index * 47) % 360;
  return HSLColor.fromAHSL(1, hue.toDouble(), 0.6, 0.65).toColor();
}

class _SelectionOverlay extends StatelessWidget {
  const _SelectionOverlay({
    required this.node,
    required this.size,
    required this.onRectChanged,
  });

  final SceneNode node;
  final Size size;
  final ValueChanged<SceneRect> onRectChanged;

  @override
  Widget build(BuildContext context) {
    final rect = Rect.fromLTWH(
      node.rect.x * size.width,
      node.rect.y * size.height,
      node.rect.width * size.width,
      node.rect.height * size.height,
    );
    return Positioned.fromRect(
      rect: rect,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) =>
                  onRectChanged(_move(node.rect, details.delta)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.lightBlueAccent, width: 2),
                ),
              ),
            ),
          ),
          Positioned(
            right: -7,
            bottom: -7,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) =>
                  onRectChanged(_resize(node.rect, details.delta)),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.lightBlueAccent,
                  border: Border.all(color: Colors.black54),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  SceneRect _move(SceneRect rect, Offset delta) {
    final dx = delta.dx / size.width;
    final dy = delta.dy / size.height;
    return rect.copyWith(
      x: (rect.x + dx).clamp(0.0, 1.0 - rect.width),
      y: (rect.y + dy).clamp(0.0, 1.0 - rect.height),
    );
  }

  SceneRect _resize(SceneRect rect, Offset delta) {
    final dw = delta.dx / size.width;
    final dh = delta.dy / size.height;
    return rect.copyWith(
      width: (rect.width + dw).clamp(0.02, 1.0 - rect.x),
      height: (rect.height + dh).clamp(0.02, 1.0 - rect.y),
    );
  }
}
