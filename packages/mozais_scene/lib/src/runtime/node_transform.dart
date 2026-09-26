import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

/// The axis-aligned rect a node occupies in the scene before its transform.
///
/// Includes the minimum hit target applied to interactive nodes.
Rect sceneNodeRect({
  required SceneNode node,
  required Size sceneSize,
  required EdgeInsets safeArea,
  required double minHitTarget,
}) {
  final availableWidth = math.max(0.0, sceneSize.width - safeArea.horizontal);
  final availableHeight = math.max(0.0, sceneSize.height - safeArea.vertical);
  var width = availableWidth * node.rect.width;
  var height = availableHeight * node.rect.height;
  final left = safeArea.left + availableWidth * node.rect.x;
  final top = safeArea.top + availableHeight * node.rect.y;

  if (node.interactive) {
    width = math.max(width, minHitTarget);
    height = math.max(height, minHitTarget);
  }

  return Rect.fromLTWH(left, top, width, height);
}

/// The effective transform applied to a node's child.
///
/// The matrix is expressed in the node's local coordinates, whose origin is
/// the node rect's top-left corner, and already includes the pivot alignment.
/// A caller can pass it straight to `Transform` without an `alignment`.
Matrix4 sceneNodeTransformMatrix(SceneTransform transform, Size size) {
  if (transform.isIdentity) {
    return Matrix4.identity();
  }

  final originX = transform.pivotX * size.width;
  final originY = transform.pivotY * size.height;
  final matrix = Matrix4.identity()
    ..translateByDouble(transform.translateX, transform.translateY, 0, 1)
    ..scaleByDouble(transform.scaleX, transform.scaleY, 1, 1)
    ..rotateX(transform.rotationX * math.pi / 180)
    ..rotateY(transform.rotationY * math.pi / 180)
    ..rotateZ(transform.rotationZ * math.pi / 180);

  if (transform.perspective != 0) {
    matrix.setEntry(3, 2, transform.perspective);
  }

  return Matrix4.identity()
    ..translateByDouble(originX, originY, 0, 1)
    ..multiply(matrix)
    ..translateByDouble(-originX, -originY, 0, 1);
}
