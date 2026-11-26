import 'package:flutter/widgets.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_tree_operations.dart';
import '../model/node_geometry.dart';
import '../model/studio_input.dart';
import 'smart_guides.dart';

/// One gesture owns its source and transient result together. Calculations
/// always use the gesture's source, while notifications compare the last result.
class PreviewNodeDrag {
  PreviewNodeDrag({
    required this.source,
    required this.canvas,
    required this.start,
    required this.tool,
    this.handle,
    required this.parentSize,
    required this.parentInverse,
  }) : preview = source;

  final SceneNode source;
  final RenderBox canvas;
  final Offset start;
  final Size parentSize;
  final Matrix4 parentInverse;
  final StudioCanvasTool tool;
  final NodeResizeHandle? handle;
  SceneNode preview;
  SceneRect? movementBounds;

  SceneNode calculateNode(
    Offset globalPosition, {
    required bool lockAspectRatio,
    required double minHitTarget,
    double? gridSize,
  }) {
    // Convert through the canvas so node transforms and viewport zoom do not
    // change the direction or speed of the pointer's movement.
    final delta =
        MatrixUtils.transformPoint(
          parentInverse,
          canvas.globalToLocal(globalPosition),
        ) -
        MatrixUtils.transformPoint(parentInverse, start);
    if (handle case final handle?) {
      return calculateResizedNode(
        source: source,
        canvasSize: parentSize,
        handle: handle,
        delta: delta,
        lockAspectRatio: lockAspectRatio,
        minHitTarget: minHitTarget,
        gridSize: gridSize,
      );
    }
    return switch (tool) {
      StudioCanvasTool.move => _calculateMovedNode(delta, gridSize),
      StudioCanvasTool.scale => source.copyWith(
        transform: source.transform.copyWith(
          scaleX: _calculateScale(
            source.transform.scaleX,
            delta.dx / canvas.size.width,
          ),
          scaleY: _calculateScale(
            source.transform.scaleY,
            delta.dy / canvas.size.height,
          ),
        ),
      ),
      StudioCanvasTool.rotate => source.copyWith(
        transform: source.transform.copyWith(
          rotationZ:
              source.transform.rotationZ + 360 * delta.dx / canvas.size.width,
        ),
      ),
      StudioCanvasTool.rotate3d => source.copyWith(
        transform: source.transform.copyWith(
          rotationX:
              source.transform.rotationX - 180 * delta.dy / canvas.size.height,
          rotationY:
              source.transform.rotationY + 180 * delta.dx / canvas.size.width,
        ),
      ),
    };
  }

  SceneNode _calculateMovedNode(Offset delta, double? gridSize) {
    final bounds = movementBounds ?? source.rect;
    final moved = calculateMovedRect(
      rect: bounds,
      canvasSize: parentSize,
      delta: delta,
      gridSize: gridSize,
    );
    return source.copyWith(
      rect: source.rect.copyWith(
        x: source.rect.x + moved.x - bounds.x,
        y: source.rect.y + moved.y - bounds.y,
      ),
    );
  }

  bool hasGeometryChange(SceneNode node) =>
      node.rect.x != preview.rect.x ||
      node.rect.y != preview.rect.y ||
      node.rect.width != preview.rect.width ||
      node.rect.height != preview.rect.height ||
      node.transform.scaleX != preview.transform.scaleX ||
      node.transform.scaleY != preview.transform.scaleY ||
      node.transform.rotationX != preview.transform.rotationX ||
      node.transform.rotationY != preview.transform.rotationY ||
      node.transform.rotationZ != preview.transform.rotationZ;

  // Retain mirrored axes and keep scale usable at the canvas edge. Scaling
  // changes the transform, while resizing changes the component's layout rect.
  double _calculateScale(double source, double delta) =>
      (source < 0 ? -1 : 1) * (source.abs() + delta * 3).clamp(0.01, 100.0);
}

PreviewNodeDrag createPreviewNodeDrag({
  required SceneDocument document,
  required Map<String, SceneNodeGeometry> geometry,
  required SceneNode node,
  required RenderBox canvas,
  required Offset start,
  required StudioCanvasTool tool,
  required NodeResizeHandle? handle,
  required EdgeInsets rootSafeArea,
}) {
  final parent = node.parentId == null
      ? null
      : document.nodes.firstWhere((entry) => entry.id == node.parentId);
  final padding = parent == null
      ? getEffectiveSceneSafeArea(document.canvas, rootSafeArea)
      : EdgeInsets.all(parent.layout!.padding);
  final parentSize = parent == null
      ? canvas.size
      : geometry[parent.id]!.rect.size;
  final parentMatrix =
      (parent == null
            ? Matrix4.identity()
            : geometry[parent.id]!.worldTransform.clone())
        ..translateByDouble(padding.left, padding.top, 0, 1);
  return PreviewNodeDrag(
    source: node,
    canvas: canvas,
    start: start,
    tool: tool,
    handle: handle,
    parentSize: calculateSceneContainerContentRect(parentSize, padding).size,
    parentInverse: tryInvertMatrix(parentMatrix) ?? Matrix4.identity(),
  );
}

void assignGroupMovementBounds({
  required List<PreviewNodeDrag> drags,
  required SceneDocument document,
  required Map<String, SceneNodeGeometry> geometry,
  required SceneNode? parent,
  required EdgeInsets rootSafeArea,
}) {
  final bounds = drags
      .map((drag) => geometry[drag.source.id]!.rect)
      .reduce((a, b) => a.expandToInclude(b));
  final insets = parent == null
      ? getEffectiveSceneSafeArea(document.canvas, rootSafeArea)
      : EdgeInsets.all(parent.layout!.padding);
  final size = drags.first.parentSize;
  final rect = SceneRect(
    x: (bounds.left - insets.left) / size.width,
    y: (bounds.top - insets.top) / size.height,
    width: bounds.width / size.width,
    height: bounds.height / size.height,
  );
  for (final drag in drags) {
    drag.movementBounds = rect;
  }
}

SmartGuideResult calculatePreviewDragSnap({
  required SceneDocument document,
  required PreviewNodeDrag primaryDrag,
  required List<SceneNode> movedNodes,
  required Map<String, SceneNodeGeometry> Function(SceneDocument)
  calculateGeometry,
  required Set<ScenePredicate> activePredicates,
  required bool Function(SceneNode, Set<ScenePredicate>) isNodeVisible,
  required double viewportScale,
  required bool showRulers,
}) {
  final ids = getDescendantIds(document, movedNodes.map((node) => node.id));
  final candidates = {for (final node in movedNodes) node.id: node};
  final geometry = calculateGeometry(
    document.copyWith(
      nodes: [for (final node in document.nodes) candidates[node.id] ?? node],
    ),
  );
  final moving = movedNodes
      .map((node) => geometry[node.id]!.bounds)
      .reduce((a, b) => a.expandToInclude(b));
  return calculateSmartGuides(
    moving: moving,
    targets: [
      for (final node in document.nodes)
        if (!ids.contains(node.id) &&
            node.id != primaryDrag.source.parentId &&
            isNodeVisible(node, activePredicates))
          geometry[node.id]!.bounds,
    ],
    canvasSize: primaryDrag.canvas.size,
    tolerance: 6 / viewportScale,
    verticalGuides: showRulers
        ? document.guides
              .where((guide) => guide.axis == SceneGuideAxis.vertical)
              .map((guide) => guide.position * primaryDrag.canvas.size.width)
        : const [],
    horizontalGuides: showRulers
        ? document.guides
              .where((guide) => guide.axis == SceneGuideAxis.horizontal)
              .map((guide) => guide.position * primaryDrag.canvas.size.height)
        : const [],
  );
}
