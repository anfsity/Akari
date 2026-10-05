import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:scene/scene.dart';

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
    x: (x / canvasSize.width).clamp(0.0, 1.0 - rect.width),
    y: (y / canvasSize.height).clamp(0.0, 1.0 - rect.height),
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

bool hasResizableProjection(SceneNode node, Size size) {
  final matrix = sceneNodeTransformMatrix(node.transform, size);
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
  final rect = Rect.fromLTWH(
    source.rect.x * canvasSize.width,
    source.rect.y * canvasSize.height,
    source.rect.width * canvasSize.width,
    source.rect.height * canvasSize.height,
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
    final ratio = alignment.x == 0
        ? heightRatio
        : alignment.y == 0
        ? widthRatio
        : (widthRatio - 1).abs() >= (heightRatio - 1).abs()
        ? widthRatio
        : heightRatio;
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
    // Stop at the canvas boundary without moving the anchored edge or
    // changing the aspect ratio. The source rect is already validated.
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
  return source.copyWith(rect: resized);
}
