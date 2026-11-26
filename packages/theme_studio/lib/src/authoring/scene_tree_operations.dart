import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../model/node_geometry.dart';
import 'studio_components.dart';

typedef SceneMutationResult = ({
  SceneDocument document,
  String selectedId,
  Set<String> selectedIds,
});

Size getSceneReferenceSize(SceneDocument document) => Size(
  document.canvas.referenceWidth.toDouble(),
  document.canvas.referenceHeight.toDouble(),
);

Rect calculateSceneContainerContentRect(Size containerSize, EdgeInsets insets) {
  final content = calculateSceneContentRect(containerSize, insets);
  return Rect.fromLTWH(
    content.left,
    content.top,
    math.max(1, content.width),
    math.max(1, content.height),
  );
}

SceneLayout getParentSceneLayout(SceneDocument document, SceneNode node) =>
    node.parentId == null
    ? const SceneLayout()
    : document.nodes.firstWhere((parent) => parent.id == node.parentId).layout!;

Offset getSceneParentContentOrigin(
  SceneDocument document,
  SceneNode node,
  EdgeInsets safeArea,
) => node.parentId == null
    ? getEffectiveSceneSafeArea(document.canvas, safeArea).topLeft
    : Offset(
        getParentSceneLayout(document, node).padding,
        getParentSceneLayout(document, node).padding,
      );

Size getSceneParentContentSize(
  SceneDocument document,
  SceneNode node,
  Map<String, SceneNodeGeometry> geometry,
  EdgeInsets safeArea,
) {
  if (node.parentId == null) {
    return calculateSceneContainerContentRect(
      getSceneReferenceSize(document),
      getEffectiveSceneSafeArea(document.canvas, safeArea),
    ).size;
  }
  return calculateSceneContainerContentRect(
    geometry[node.parentId]!.rect.size,
    EdgeInsets.all(getParentSceneLayout(document, node).padding),
  ).size;
}

List<SceneNode> getSceneSelectionRoots(
  SceneDocument document,
  List<SceneNode> selectedNodes,
  Set<String> selectedIds,
) {
  final byId = {for (final node in document.nodes) node.id: node};
  return selectedNodes.where((node) {
    var parent = node.parentId;
    while (parent != null) {
      if (selectedIds.contains(parent)) return false;
      parent = byId[parent]!.parentId;
    }
    return true;
  }).toList();
}

List<SceneNode> getSceneSelectionLayoutNodes(
  SceneDocument document,
  List<SceneNode> selectedNodes,
  Map<String, SceneNodeGeometry> geometry,
  EdgeInsets safeArea,
) {
  final result = <SceneNode>[];
  for (final node in selectedNodes) {
    final rect = geometry[node.id]!.rect;
    final size = getSceneParentContentSize(document, node, geometry, safeArea);
    final origin = getSceneParentContentOrigin(document, node, safeArea);
    result.add(
      node.copyWith(
        rect: SceneRect(
          x: (rect.left - origin.dx) / size.width,
          y: (rect.top - origin.dy) / size.height,
          width: rect.width / size.width,
          height: rect.height / size.height,
        ),
      ),
    );
  }
  return result;
}

Set<String> getReservedSceneIds(
  SceneDocument document,
  ThemeLayoutDefinition? layout,
) => {
  for (final node in document.nodes) node.id,
  for (final slot in layout?.slots ?? const <ThemeLayoutSlot>[])
    slot.defaultNode.id,
};

String allocateSceneId(String base, Set<String> ids) {
  var id = base;
  var suffix = 2;
  while (ids.contains(id)) {
    id = '$base-${suffix++}';
  }
  ids.add(id);
  return id;
}

Matrix4? tryInvertMatrix(Matrix4 matrix) {
  final inverse = Matrix4.zero();
  final determinant = inverse.copyInverse(matrix);
  if (determinant == 0 || !determinant.isFinite) return null;
  return inverse;
}

SceneRect clampNormalizedRect({
  required double x,
  required double y,
  required double width,
  required double height,
}) {
  final safeWidth = width.clamp(1e-6, 1.0);
  final safeHeight = height.clamp(1e-6, 1.0);
  var safeX = x.clamp(0.0, 1.0 - safeWidth);
  var safeY = y.clamp(0.0, 1.0 - safeHeight);
  if (safeX + safeWidth > 1.0) {
    safeX = math.max(0.0, 1.0 - safeWidth);
  }
  if (safeY + safeHeight > 1.0) {
    safeY = math.max(0.0, 1.0 - safeHeight);
  }
  return SceneRect(
    x: safeX,
    y: safeY,
    width: safeX + safeWidth > 1.0 ? 1.0 - safeX : safeWidth,
    height: safeY + safeHeight > 1.0 ? 1.0 - safeY : safeHeight,
  );
}

SceneMutationResult buildGroupedDocument({
  required SceneDocument document,
  required String? parentId,
  required List<SceneNode> layoutNodes,
  required Set<String> selectedIds,
  required Set<String> reservedIds,
}) {
  final byId = {for (final node in layoutNodes) node.id: node};
  final left = layoutNodes.map((node) => node.rect.x).reduce(math.min);
  final top = layoutNodes.map((node) => node.rect.y).reduce(math.min);
  final right = layoutNodes
      .map((node) => node.rect.x + node.rect.width)
      .reduce(math.max);
  final bottom = layoutNodes
      .map((node) => node.rect.y + node.rect.height)
      .reduce(math.max);
  final id = allocateSceneId('frame', reservedIds);
  final frame = SceneNode(
    id: id,
    componentId: 'frame',
    parentId: parentId,
    rect: SceneRect(x: left, y: top, width: right - left, height: bottom - top),
    layout: const SceneLayout(),
    renderOrder: layoutNodes.map((node) => node.renderOrder).reduce(math.max),
  );
  return (
    document: document.copyWith(
      nodes: [
        for (final node in document.nodes)
          if (selectedIds.contains(node.id))
            node.copyWith(
              parentId: id,
              rect: getRelativeRect(byId[node.id]!.rect, frame.rect),
            )
          else
            node,
        frame,
      ],
    ),
    selectedId: id,
    selectedIds: {id},
  );
}

SceneMutationResult buildUngroupedDocument({
  required SceneDocument document,
  required SceneNode frame,
  required List<SceneNode> children,
  required Map<String, SceneNodeGeometry> geometry,
  required EdgeInsets safeArea,
}) {
  final frameRect = geometry[frame.id]!.rect;
  final parentSize = getSceneParentContentSize(
    document,
    frame,
    geometry,
    safeArea,
  );
  final parentOrigin = getSceneParentContentOrigin(document, frame, safeArea);
  final replacements = {
    for (final node in children)
      node.id: node.copyWith(
        parentId: frame.parentId,
        rect: clampNormalizedRect(
          x:
              (frameRect.left -
                  parentOrigin.dx +
                  geometry[node.id]!.rect.left) /
              parentSize.width,
          y:
              (frameRect.top - parentOrigin.dy + geometry[node.id]!.rect.top) /
              parentSize.height,
          width: geometry[node.id]!.rect.width / parentSize.width,
          height: geometry[node.id]!.rect.height / parentSize.height,
        ),
      ),
  };
  return (
    document: document.copyWith(
      nodes: [
        for (final node in document.nodes)
          if (node.id != frame.id) replacements[node.id] ?? node,
      ],
    ),
    selectedId: children.last.id,
    selectedIds: children.map((node) => node.id).toSet(),
  );
}

SceneMutationResult buildPlacedNodeDocument({
  required SceneDocument document,
  required SceneNode template,
  required Offset position,
}) {
  final existing = document.nodes
      .where((node) => node.id == template.id)
      .firstOrNull;
  final node = existing ?? template;
  final rect = node.rect.copyWith(
    x: position.dx.clamp(0.0, 1 - node.rect.width),
    y: position.dy.clamp(0.0, 1 - node.rect.height),
  );
  final placed = node.copyWith(parentId: null, rect: rect);
  return (
    document: document.copyWith(
      nodes: [
        for (final current in document.nodes)
          if (current.id == node.id) placed else current,
        if (existing == null) placed,
      ],
    ),
    selectedId: node.id,
    selectedIds: {node.id},
  );
}

SceneMutationResult buildCreatedComponentDocument({
  required SceneDocument document,
  required StudioComponent component,
  required Offset position,
  required Set<String> reservedIds,
}) {
  final primitive = component.primitive;
  final base = primitive?.name ?? 'frame';
  final id = allocateSceneId(base, reservedIds);
  final token = allocateSceneId('$id-style', document.styleTokens.keys.toSet());
  final node = SceneNode(
    id: id,
    componentId: primitive == null ? 'frame' : 'scenePrimitive',
    primitive: primitive,
    layout: primitive == null ? const SceneLayout() : null,
    styleToken: token,
    rect: SceneRect(
      x: position.dx.clamp(0, .7),
      y: position.dy.clamp(0, .7),
      width: .3,
      height: primitive == ScenePrimitive.text ? .08 : .3,
    ),
    properties: primitive == ScenePrimitive.text
        ? const {'text': 'New text'}
        : const {},
  );
  return (
    document: document.copyWith(
      nodes: [...document.nodes, node],
      styleTokens: {
        ...document.styleTokens,
        token: primitive == ScenePrimitive.text
            ? const SceneStyle(textColor: 0xffffffff, fontSize: 32)
            : SceneStyle(fill: primitive == null ? 0x00000000 : 0xffa1a1aa),
      },
    ),
    selectedId: id,
    selectedIds: {id},
  );
}

SceneMutationResult buildCreatedAssetDocument({
  required SceneDocument document,
  required SceneAsset asset,
  required Set<String> reservedIds,
}) {
  final name = asset.path.split('/').last;
  final dot = name.lastIndexOf('.');
  final id = allocateSceneId(
    dot > 0 ? name.substring(0, dot) : name,
    reservedIds,
  );
  final node = SceneNode(
    id: id,
    componentId: 'sceneAsset',
    asset: asset,
    rect: const SceneRect(x: .35, y: .35, width: .3, height: .3),
  );
  return (
    document: document.copyWith(nodes: [...document.nodes, node]),
    selectedId: id,
    selectedIds: {id},
  );
}

String? getSceneLayerMoveBlockReason(
  SceneDocument document,
  String id,
  String? parentId,
) {
  var ancestor = parentId;
  while (ancestor != null) {
    if (ancestor == id) {
      return 'A frame cannot contain itself or its ancestors.';
    }
    final parent = document.nodes.firstWhere((node) => node.id == ancestor);
    if (parent.layout == null) return 'Drop inside a frame to nest a layer.';
    ancestor = parent.parentId;
  }
  return null;
}

SceneMutationResult buildMovedLayerDocument({
  required SceneDocument document,
  required String id,
  required String? parentId,
  required String? beforeId,
  required Map<String, SceneNodeGeometry> Function() calculateGeometry,
  required EdgeInsets safeArea,
}) {
  var node = document.nodes.firstWhere((node) => node.id == id);
  if (node.parentId != parentId) {
    final geometry = calculateGeometry();
    final parent = parentId == null
        ? null
        : document.nodes.firstWhere((node) => node.id == parentId);
    final effectiveSafeArea = getEffectiveSceneSafeArea(
      document.canvas,
      safeArea,
    );
    final content = parent == null
        ? calculateSceneContainerContentRect(
            getSceneReferenceSize(document),
            effectiveSafeArea,
          ).size
        : calculateSceneContainerContentRect(
            geometry[parent.id]!.rect.size,
            EdgeInsets.all(parent.layout!.padding),
          ).size;
    final oldParent = node.parentId == null
        ? Matrix4.identity()
        : geometry[node.parentId]!.worldTransform;
    final newParent = parent == null
        ? Matrix4.identity()
        : geometry[parent.id]!.worldTransform;
    final inverse = tryInvertMatrix(newParent);
    final origin = inverse != null
        ? MatrixUtils.transformPoint(
            inverse,
            MatrixUtils.transformPoint(oldParent, geometry[id]!.rect.topLeft),
          )
        : geometry[id]!.bounds.topLeft -
              (parent == null
                  ? Offset.zero
                  : geometry[parent.id]!.bounds.topLeft);
    final originOffset = parent == null
        ? effectiveSafeArea.topLeft
        : Offset(parent.layout!.padding, parent.layout!.padding);
    node = node.copyWith(
      parentId: parentId,
      rect: clampNormalizedRect(
        x: (origin.dx - originOffset.dx) / content.width,
        y: (origin.dy - originOffset.dy) / content.height,
        width: geometry[id]!.rect.width / content.width,
        height: geometry[id]!.rect.height / content.height,
      ),
    );
  }
  final siblings = document
      .getChildren(parentId)
      .reversed
      .where((node) => node.id != id)
      .toList();
  final rawIndex = beforeId == null
      ? -1
      : siblings.indexWhere((node) => node.id == beforeId);
  final index = rawIndex < 0 ? siblings.length : rawIndex;
  siblings.insert(index, node);
  final ranks = {
    for (final (index, node) in siblings.reversed.indexed) node.id: index,
  };
  return (
    document: document.copyWith(
      nodes: [
        for (final current in document.nodes)
          if (ranks.containsKey(current.id))
            (current.id == id ? node : current).copyWith(
              renderOrder: ranks[current.id],
            )
          else
            current,
      ],
    ),
    selectedId: id,
    selectedIds: {id},
  );
}

SceneMutationResult buildDuplicatedSelectionDocument({
  required SceneDocument document,
  required List<SceneNode> subtree,
  required String selectedId,
  required Set<String> selectedIds,
  required Set<String> reservedIds,
}) {
  final copies = {
    for (final node in subtree)
      node.id: allocateSceneId('${node.id}-copy', reservedIds),
  };
  return (
    document: document.copyWith(
      nodes: [
        for (final node in document.nodes) ...[
          node,
          if (copies.containsKey(node.id))
            node.copyWith(
              id: copies[node.id],
              parentId: copies[node.parentId] ?? node.parentId,
            ),
        ],
      ],
    ),
    selectedId: copies[selectedId]!,
    selectedIds: {for (final id in selectedIds) copies[id]!},
  );
}

SceneMutationResult buildRemovedNodesDocument({
  required SceneDocument document,
  required Set<String> removedIds,
  required String primaryTargetId,
  required String currentSelectedId,
  required Set<String> currentSelectedIds,
  required bool collapseSelectionToNext,
}) {
  final index = document.nodes.indexWhere((node) => node.id == primaryTargetId);
  final nodes = document.nodes
      .where((node) => !removedIds.contains(node.id))
      .toList();
  final next = nodes[math.min(index, nodes.length - 1)].id;
  if (collapseSelectionToNext) {
    return (
      document: document.copyWith(nodes: nodes),
      selectedId: next,
      selectedIds: {next},
    );
  }
  final remainingSelection = currentSelectedIds.difference(removedIds);
  return (
    document: document.copyWith(nodes: nodes),
    selectedId: removedIds.contains(currentSelectedId)
        ? next
        : currentSelectedId,
    selectedIds: remainingSelection.isEmpty ? {next} : remainingSelection,
  );
}
