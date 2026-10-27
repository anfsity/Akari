import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:scene_schema/scene_schema.dart';

import 'node_transform.dart';

/// One authoritative layout calculation for production and authoring tools.
/// Rectangles are parent-local; world transforms include all ancestor frames.
class SceneNodeGeometry {
  const SceneNodeGeometry({required this.rect, required this.worldTransform});

  final Rect rect;
  final Matrix4 worldTransform;
  Rect get bounds =>
      MatrixUtils.transformRect(worldTransform, Offset.zero & rect.size);
}

Map<String, SceneNodeGeometry> calculateSceneLayout({
  required SceneDocument document,
  required Size size,
  EdgeInsets safeArea = EdgeInsets.zero,
  double minHitTarget = 44,
}) {
  final result = <String, SceneNodeGeometry>{};
  final children = <String?, List<SceneNode>>{};
  for (final node in document.paintOrder) {
    children.putIfAbsent(node.parentId, () => []).add(node);
  }

  void place(
    String? parentId,
    Size size,
    Matrix4 parentTransform,
    SceneLayout layout,
    EdgeInsets insets,
  ) {
    final nodes = children[parentId] ?? const [];
    final content = Rect.fromLTWH(
      insets.left,
      insets.top,
      math.max(0, size.width - insets.horizontal),
      math.max(0, size.height - insets.vertical),
    );
    final row = layout.direction == SceneLayoutDirection.row;
    final flow = layout.direction != SceneLayoutDirection.absolute;
    final main = row ? content.width : content.height;
    final cross = row ? content.height : content.width;
    Size getSize(SceneNode node) => Size(
      math.max(
        node.interactive ? minHitTarget : 0,
        node.sizing.width ?? content.width * node.rect.width,
      ),
      math.max(
        node.interactive ? minHitTarget : 0,
        node.sizing.height ?? content.height * node.rect.height,
      ),
    );
    final sizes = {for (final node in nodes) node.id: getSize(node)};
    final gaps = math.max(0, nodes.length - 1) * layout.gap;
    var fixed = gaps;
    var flex = 0.0;
    if (flow) {
      for (final node in nodes) {
        if (node.sizing.flex > 0) {
          flex += node.sizing.flex;
          fixed += node.interactive ? minHitTarget : 0;
        } else {
          fixed += row ? sizes[node.id]!.width : sizes[node.id]!.height;
        }
      }
    }
    final remaining = math.max(0.0, main - fixed);
    final spare = flex > 0 ? 0.0 : remaining;
    var cursor = switch (layout.mainAlignment) {
      SceneMainAlignment.center => spare / 2,
      SceneMainAlignment.end => spare,
      _ => 0.0,
    };
    final gap =
        layout.gap +
        (layout.mainAlignment == SceneMainAlignment.spaceBetween &&
                nodes.length > 1
            ? spare / (nodes.length - 1)
            : 0);
    for (final node in nodes) {
      var nodeSize = sizes[node.id]!;
      late Rect rect;
      if (flow) {
        final mainSize = node.sizing.flex > 0
            ? (node.interactive ? minHitTarget : 0) +
                  remaining * node.sizing.flex / flex
            : row
            ? nodeSize.width
            : nodeSize.height;
        final crossSize = layout.crossAlignment == SceneCrossAlignment.stretch
            ? cross
            : row
            ? nodeSize.height
            : nodeSize.width;
        final crossOffset = switch (layout.crossAlignment) {
          SceneCrossAlignment.center => (cross - crossSize) / 2,
          SceneCrossAlignment.end => cross - crossSize,
          _ => 0.0,
        };
        nodeSize = row ? Size(mainSize, crossSize) : Size(crossSize, mainSize);
        rect =
            (content.topLeft +
                (row
                    ? Offset(cursor, crossOffset)
                    : Offset(crossOffset, cursor))) &
            nodeSize;
        cursor += mainSize + gap;
      } else {
        rect =
            (content.topLeft +
                Offset(
                  content.width * node.rect.x,
                  content.height * node.rect.y,
                )) &
            nodeSize;
      }
      final transform = parentTransform.clone()
        ..translateByDouble(rect.left, rect.top, 0, 1)
        ..multiply(sceneNodeTransformMatrix(node.transform, rect.size));
      result[node.id] = SceneNodeGeometry(
        rect: rect,
        worldTransform: transform,
      );
      if (node.layout case final layout?) {
        place(
          node.id,
          rect.size,
          transform,
          layout,
          EdgeInsets.all(layout.padding),
        );
      }
    }
  }

  place(
    null,
    size,
    Matrix4.identity(),
    const SceneLayout(),
    document.canvas.useSafeArea ? safeArea : EdgeInsets.zero,
  );
  return result;
}
