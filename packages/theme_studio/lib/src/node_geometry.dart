import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:scene/scene.dart';

const minStudioZoom = 0.05;
const maxStudioZoom = 8.0;

double clampStudioZoom(double zoom) => zoom.clamp(minStudioZoom, maxStudioZoom);

double calculateFitZoom({
  required Size viewportSize,
  required Size referenceSize,
}) => math.min(
  viewportSize.width / referenceSize.width,
  viewportSize.height / referenceSize.height,
);

enum NodeAlignment { left, center, right, top, middle, bottom }

SceneRect getRelativeRect(SceneRect rect, SceneRect parent) {
  final x = ((rect.x - parent.x) / parent.width).clamp(0.0, 1.0);
  final y = ((rect.y - parent.y) / parent.height).clamp(0.0, 1.0);
  return SceneRect(
    x: x,
    y: y,
    width: math.min(rect.width / parent.width, 1 - x),
    height: math.min(rect.height / parent.height, 1 - y),
  );
}

List<SceneNode> calculateAlignedNodes(
  List<SceneNode> nodes,
  NodeAlignment alignment,
) {
  final left = nodes.map((node) => node.rect.x).reduce(math.min);
  final right = nodes
      .map((node) => node.rect.x + node.rect.width)
      .reduce(math.max);
  final top = nodes.map((node) => node.rect.y).reduce(math.min);
  final bottom = nodes
      .map((node) => node.rect.y + node.rect.height)
      .reduce(math.max);
  return [
    for (final node in nodes)
      node.copyWith(
        rect: node.rect.copyWith(
          x: switch (alignment) {
            NodeAlignment.left => left,
            NodeAlignment.center => (left + right - node.rect.width) / 2,
            NodeAlignment.right => right - node.rect.width,
            _ => node.rect.x,
          },
          y: switch (alignment) {
            NodeAlignment.top => top,
            NodeAlignment.middle => (top + bottom - node.rect.height) / 2,
            NodeAlignment.bottom => bottom - node.rect.height,
            _ => node.rect.y,
          },
        ),
      ),
  ];
}

List<SceneNode> calculateDistributedNodes(
  List<SceneNode> nodes, {
  required bool horizontal,
}) {
  final sorted = [...nodes]
    ..sort(
      (a, b) => horizontal
          ? a.rect.x.compareTo(b.rect.x)
          : a.rect.y.compareTo(b.rect.y),
    );
  final start = horizontal ? sorted.first.rect.x : sorted.first.rect.y;
  final last = sorted.last.rect;
  final end = horizontal ? last.x + last.width : last.y + last.height;
  final occupied = sorted.fold(
    0.0,
    (sum, node) => sum + (horizontal ? node.rect.width : node.rect.height),
  );
  final gap = (end - start - occupied) / (nodes.length - 1);
  var cursor = start;
  final result = <SceneNode>[];
  for (final node in sorted) {
    final rect = node.rect.copyWith(
      x: horizontal ? cursor : null,
      y: horizontal ? null : cursor,
    );
    cursor += (horizontal ? node.rect.width : node.rect.height) + gap;
    result.add(node.copyWith(rect: rect));
  }
  return result;
}

SceneRect calculateMovedRect({
  required SceneRect rect,
  required Size canvasSize,
  required Offset delta,
  double? gridSize,
}) {
  var x = rect.x * canvasSize.width + delta.dx;
  var y = rect.y * canvasSize.height + delta.dy;
  if (gridSize != null) {
    x = (x / gridSize).round() * gridSize;
    y = (y / gridSize).round() * gridSize;
  }
  return rect.copyWith(
    x: (x / canvasSize.width).clamp(0.0, math.max(0.0, 1.0 - rect.width)),
    y: (y / canvasSize.height).clamp(0.0, math.max(0.0, 1.0 - rect.height)),
  );
}

enum NodeResizeHandle {
  topLeft(Alignment.topLeft, SystemMouseCursors.resizeUpLeftDownRight),
  top(Alignment.topCenter, SystemMouseCursors.resizeUpDown),
  topRight(Alignment.topRight, SystemMouseCursors.resizeUpRightDownLeft),
  right(Alignment.centerRight, SystemMouseCursors.resizeLeftRight),
  bottomRight(Alignment.bottomRight, SystemMouseCursors.resizeUpLeftDownRight),
  bottom(Alignment.bottomCenter, SystemMouseCursors.resizeUpDown),
  bottomLeft(Alignment.bottomLeft, SystemMouseCursors.resizeUpRightDownLeft),
  left(Alignment.centerLeft, SystemMouseCursors.resizeLeftRight);

  const NodeResizeHandle(this.alignment, this.cursor);

  final Alignment alignment;
  final MouseCursor cursor;
}

bool isInvertibleEditingPlane(Matrix4 matrix) {
  // Zero scale and edge-on 3D rotations have no invertible editing plane.
  final determinant =
      matrix.entry(0, 0) *
          (matrix.entry(1, 1) * matrix.entry(3, 3) -
              matrix.entry(1, 3) * matrix.entry(3, 1)) -
      matrix.entry(0, 1) *
          (matrix.entry(1, 0) * matrix.entry(3, 3) -
              matrix.entry(1, 3) * matrix.entry(3, 0)) +
      matrix.entry(0, 3) *
          (matrix.entry(1, 0) * matrix.entry(3, 1) -
              matrix.entry(1, 1) * matrix.entry(3, 0));
  return determinant.abs() > 1e-8;
}

bool hasResizableProjection(SceneNode node, Size size) =>
    isInvertibleEditingPlane(sceneNodeTransformMatrix(node.transform, size));

Map<NodeResizeHandle, Offset> calculateHandlePoints({
  required Rect rect,
  required Matrix4 matrix,
}) => {
  for (final handle in NodeResizeHandle.values)
    handle:
        rect.topLeft +
        MatrixUtils.transformPoint(
          matrix,
          handle.alignment.alongSize(rect.size),
        ),
};

/// Resize the layout in the node's editing plane, preserving the transformed
/// opposite edge/corner. A paint transform cannot resize a text container:
/// changing the layout instead lets the component lay out its content again.
SceneNode calculateResizedNode({
  required SceneNode source,
  required Size canvasSize,
  required NodeResizeHandle handle,
  required Offset delta,
  required bool lockAspectRatio,
  required double minHitTarget,
  double? gridSize,
}) {
  final rect = sceneNodeRect(
    node: source,
    sceneSize: canvasSize,
    safeArea: EdgeInsets.zero,
    minHitTarget: minHitTarget,
  );
  final matrix = sceneNodeTransformMatrix(source.transform, rect.size);
  final alignment = handle.alignment;
  final start = MatrixUtils.transformPoint(
    matrix,
    alignment.alongSize(rect.size),
  );
  var target = rect.topLeft + start + delta;
  if (gridSize != null) {
    target = Offset(
      (target.dx / gridSize).round() * gridSize,
      (target.dy / gridSize).round() * gridSize,
    );
  }
  final point = target - rect.topLeft;
  // Invert the 2D projective plane. Inverting a 4D matrix at z=0 would give
  // incorrect pointer coordinates for perspective and X/Y rotations.
  final a = matrix.entry(0, 0) - point.dx * matrix.entry(3, 0);
  final b = matrix.entry(0, 1) - point.dx * matrix.entry(3, 1);
  final c = matrix.entry(1, 0) - point.dy * matrix.entry(3, 0);
  final d = matrix.entry(1, 1) - point.dy * matrix.entry(3, 1);
  final u = point.dx * matrix.entry(3, 3) - matrix.entry(0, 3);
  final v = point.dy * matrix.entry(3, 3) - matrix.entry(1, 3);
  final determinant = a * d - b * c;
  // A pointer can reach the projection's horizon even for a valid source.
  if (determinant.abs() < 1e-8) return source;
  final local = Offset(
    (u * d - b * v) / determinant,
    (a * v - u * c) / determinant,
  );
  final localDelta = local - alignment.alongSize(rect.size);
  var width = rect.width + localDelta.dx * alignment.x;
  var height = rect.height + localDelta.dy * alignment.y;
  final minimum = source.interactive ? minHitTarget : 1.0;
  if (lockAspectRatio) {
    final widthRatio = width / rect.width;
    final heightRatio = height / rect.height;
    final double ratio;
    if (alignment.x == 0) {
      ratio = heightRatio;
    } else if (alignment.y == 0) {
      ratio = widthRatio;
    } else {
      ratio = (widthRatio - 1).abs() >= (heightRatio - 1).abs()
          ? widthRatio
          : heightRatio;
    }
    final bounded = math.max(
      ratio,
      math.max(minimum / rect.width, minimum / rect.height),
    );
    width = rect.width * bounded;
    height = rect.height * bounded;
  } else {
    width = math.max(minimum, width);
    height = math.max(minimum, height);
  }
  final anchor = Alignment(-alignment.x, -alignment.y);
  final fixedPoint =
      rect.topLeft +
      MatrixUtils.transformPoint(matrix, anchor.alongSize(rect.size));

  SceneRect calculateRect(double fraction) {
    final size = Size(
      rect.width + (width - rect.width) * fraction,
      rect.height + (height - rect.height) * fraction,
    );
    final origin =
        fixedPoint -
        MatrixUtils.transformPoint(
          sceneNodeTransformMatrix(source.transform, size),
          anchor.alongSize(size),
        );
    return SceneRect(
      x: origin.dx / canvasSize.width,
      y: origin.dy / canvasSize.height,
      width: size.width / canvasSize.width,
      height: size.height / canvasSize.height,
    );
  }

  var resized = calculateRect(1);
  if (!resized.isNormalized) {
    // 3D rotations, perspective projection, and aspect-ratio constraints create
    // a non-linear relationship between edge delta and normalized canvas bounds.
    // Binary bisection monotonically finds the maximum reachable fraction within
    // the [0.0, 1.0] interval without moving the anchored edge.
    var lower = 0.0;
    var upper = 1.0;
    resized = source.rect;
    for (var iteration = 0; iteration < 40; iteration++) {
      final middle = (lower + upper) / 2;
      final candidate = calculateRect(middle);
      if (candidate.isNormalized) {
        lower = middle;
        resized = candidate;
      } else {
        upper = middle;
      }
    }
  }
  return source.copyWith(
    rect: resized,
    sizing: SceneSizing(
      width: source.sizing.width == null
          ? null
          : resized.width * canvasSize.width,
      height: source.sizing.height == null
          ? null
          : resized.height * canvasSize.height,
      flex: source.sizing.flex,
    ),
  );
}
