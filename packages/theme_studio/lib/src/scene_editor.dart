import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'node_inspector_controller.dart';
import 'node_geometry.dart';

// Store canonical JSON with history so status queries and undo/redo do not
// serialize the entire scene again. Selection changes reuse the same encoding.
typedef _SceneRevision = ({
  SceneDocument document,
  String encoded,
  String selectedId,
  Set<String> selectedIds,
});

/// Owns one authoring session. Only validated documents enter history, and
/// saving refuses to replace a file modified outside this session.
class SceneEditor extends ChangeNotifier {
  SceneEditor(
    this.file, {
    this._componentCatalog = const ThemeComponentCatalog(),
    this._presetCatalog = const ThemePresetCatalog(),
    ThemeLayoutDefinition? layout,
  }) : _declaredLayout = layout {
    _loadFromDisk(initial: true);
    inspector = NodeInspectorController(selectedNode, getInspectorCanvas());
  }

  final File file;
  ThemeComponentCatalog _componentCatalog;
  ThemePresetCatalog _presetCatalog;
  ThemeLayoutDefinition? _declaredLayout;
  late final NodeInspectorController inspector;
  late String _source;
  late String _savedDocument;
  late _SceneRevision _revision;
  final _undo = <_SceneRevision>[];
  final _redo = <_SceneRevision>[];
  SceneDocument? _previewDocument;

  SceneDocument get document => _revision.document;
  SceneDocument get previewDocument => _previewDocument ?? document;
  String get encodedDocument => _revision.encoded;
  String get selectedId => _revision.selectedId;
  Set<String> get selectedIds => Set.unmodifiable(_revision.selectedIds);
  List<SceneNode> get selectedNodes =>
      document.nodes.where((node) => selectedIds.contains(node.id)).toList();
  SceneNode get selectedNode =>
      document.nodes.firstWhere((node) => node.id == selectedId);
  bool get isDirty => _revision.encoded != _savedDocument;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get canDeleteNode => deletionBlockReason == null;
  bool get canDuplicateNode =>
      selectedIds.isNotEmpty &&
      getSelectionSubtree().every((node) => layout?.findSlot(node.id) == null);
  String? get deletionBlockReason {
    if (selectedIds.isEmpty) return 'Select a layer first.';
    final nodes = getSelectionSubtree();
    if (nodes.length == document.nodes.length) {
      return 'A scene needs at least one node.';
    }
    for (final node in nodes) {
      final reason = getDeletionBlockReason(node.id);
      if (reason != null) return reason;
    }
    return null;
  }

  bool get canGroup =>
      selectedNodes.length >= 2 &&
      selectedNodes.every((node) => node.parentId == selectedNode.parentId) &&
      getParentLayout(selectedNode).direction ==
          SceneLayoutDirection.absolute &&
      getSelectionLayoutNodes().every((node) => node.rect.isNormalized);
  bool get canArrange => canGroup;
  bool get canUngroup =>
      selectedIds.length == 1 &&
      selectedNode.layout?.direction == SceneLayoutDirection.absolute &&
      selectedNode.transform.isIdentity &&
      selectedNode.visibleWhen == null &&
      selectedNode.styleToken == null &&
      selectedNode.stateEffects.isEmpty &&
      selectedNode.motion == SceneMotionPreset.none &&
      !selectedNode.layout!.clip;
  ThemeComponentCatalog get componentCatalog => _componentCatalog;
  ThemePresetCatalog get presetCatalog => _presetCatalog;
  ThemeLayoutDefinition? get layout =>
      _declaredLayout?.sceneId == document.id ? _declaredLayout : null;
  List<ThemeLayoutSlot> get missingRequiredSlots =>
      layout?.findMissingRequiredSlots(document) ?? const [];

  void updateAuthoring({
    required ThemeComponentCatalog componentCatalog,
    required ThemeLayoutDefinition? layout,
    ThemePresetCatalog presetCatalog = const ThemePresetCatalog(),
  }) {
    if (identical(componentCatalog, _componentCatalog) &&
        identical(presetCatalog, _presetCatalog) &&
        identical(layout, _declaredLayout)) {
      return;
    }
    // Undo and redo trust the revision invariant too. New authoring rules must
    // accept history before replacing this session's catalog and layout.
    for (final revision in [_revision, ..._undo, ..._redo]) {
      componentCatalog.validateDocument(revision.document);
      presetCatalog.validateDocument(revision.document);
      layout?.validateDocument(revision.document);
    }
    _componentCatalog = componentCatalog;
    _presetCatalog = presetCatalog;
    _declaredLayout = layout;
    notifyListeners();
  }

  void updateThemeProperty(String name, String value) {
    if (!applyDraft()) return;
    if (!_presetCatalog.properties.any((property) => property.name == name)) {
      throw ArgumentError.value(name, 'name', 'Undeclared theme preset');
    }
    _updateDocument(
      document.copyWith(
        themeProperties: {...document.themeProperties, name: value},
      ),
      selectedId: selectedId,
    );
  }

  String? getDeletionBlockReason(String nodeId) {
    if (document.nodes.length == 1) return 'A scene needs at least one node.';
    final ids = {nodeId};
    for (final node in document.layerOrder) {
      if (ids.contains(node.parentId)) ids.add(node.id);
    }
    if (ids.length == document.nodes.length) {
      return 'A scene needs at least one node.';
    }
    for (final id in ids) {
      final slot = layout?.findSlot(id);
      if (slot != null && slot.isRequired) {
        return '${slot.label} is required by this layout.';
      }
    }
    return null;
  }

  void updateLayoutSlot(String nodeId, {required bool isPresent}) {
    if (!applyDraft()) return;
    final slot = layout?.findSlot(nodeId, document: document);
    if (slot == null) throw ArgumentError.value(nodeId, 'nodeId');
    if (document.nodes.any((node) => node.id == nodeId) == isPresent) return;
    if (!isPresent) {
      _removeNode(nodeId);
      return;
    }
    _updateDocument(
      document.copyWith(nodes: [...document.nodes, slot.defaultNode]),
      selectedId: nodeId,
    );
  }

  void updateLayoutPreset(String presetId) {
    if (!applyDraft()) return;
    final layout = this.layout;
    if (layout == null) throw StateError('This scene has no layout.');
    _updateDocument(
      layout.getDocumentWithPreset(document, presetId),
      selectedId: selectedId,
    );
  }

  void addRequiredLayoutSlots() {
    if (!applyDraft()) return;
    final missing = missingRequiredSlots;
    if (missing.isEmpty) return;
    _updateDocument(
      document.copyWith(
        nodes: [
          ...document.nodes,
          for (final slot in missing) slot.defaultNode,
        ],
      ),
      selectedId: missing.first.defaultNode.id,
    );
  }

  bool applyDraft() {
    if (!inspector.hasDraft) return true;
    try {
      updateNode(inspector.getUpdatedNode());
      if (inspector.hasDraft) inspector.resetNode(selectedNode);
      return true;
    } on FormatException catch (error) {
      inspector.showError(error.message);
      return false;
    }
  }

  bool selectNode(String id, {bool toggle = false}) {
    final ids = toggle ? {...selectedIds} : <String>{};
    if (!toggle || !ids.remove(id)) ids.add(id);
    return selectNodes(ids, primaryId: id);
  }

  bool selectNodes(Set<String> ids, {String? primaryId}) {
    if (!applyDraft()) return false;
    if (!document.nodes.map((node) => node.id).toSet().containsAll(ids)) {
      throw ArgumentError.value(ids, 'ids');
    }
    final id = ids.isEmpty
        ? selectedId
        : ids.contains(primaryId)
        ? primaryId!
        : ids.last;
    if (selectedId == id && setEquals(selectedIds, ids)) return true;
    _applyRevision((
      document: document,
      encoded: _revision.encoded,
      selectedId: id,
      selectedIds: Set.of(ids),
    ));
    return true;
  }

  void updateNode(SceneNode node) {
    updateNodes([node]);
  }

  void updateNodes(List<SceneNode> updated) {
    final replacements = {for (final node in updated) node.id: node};
    if (!document.nodes
        .map((node) => node.id)
        .toSet()
        .containsAll(replacements.keys)) {
      throw ArgumentError.value(replacements.keys, 'node ids');
    }
    _updateDocument(
      document.copyWith(
        nodes: [
          for (final node in document.nodes) replacements[node.id] ?? node,
        ],
      ),
      selectedId: selectedId,
    );
  }

  SceneLayout getParentLayout(SceneNode node) => node.parentId == null
      ? const SceneLayout()
      : document.nodes
            .firstWhere((parent) => parent.id == node.parentId)
            .layout!;

  List<SceneNode> getSelectionRoots() {
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

  List<SceneNode> getSelectionSubtree() {
    final ids = {...selectedIds};
    for (final node in document.layerOrder) {
      if (ids.contains(node.parentId)) ids.add(node.id);
    }
    return document.nodes.where((node) => ids.contains(node.id)).toList();
  }

  void moveSelection(Offset delta) {
    if (!applyDraft()) return;
    final size = Size(
      document.canvas.referenceWidth.toDouble(),
      document.canvas.referenceHeight.toDouble(),
    );
    final geometry = calculateSceneLayout(document: document, size: size);
    updateNodes([
      for (final node in getSelectionRoots())
        if (getParentLayout(node).direction == SceneLayoutDirection.absolute)
          node.copyWith(
            rect: calculateMovedRect(
              rect: node.rect,
              canvasSize: getParentContentSize(node, geometry),
              delta: delta,
            ),
          ),
    ]);
  }

  Size getParentContentSize(
    SceneNode node,
    Map<String, SceneNodeGeometry> geometry,
  ) {
    if (node.parentId == null) {
      return Size(
        document.canvas.referenceWidth.toDouble(),
        document.canvas.referenceHeight.toDouble(),
      );
    }
    final size = geometry[node.parentId]!.rect.size;
    final padding = getParentLayout(node).padding * 2;
    return Size(
      math.max(1, size.width - padding),
      math.max(1, size.height - padding),
    );
  }

  void alignSelection(NodeAlignment alignment) {
    if (!applyDraft() || !canArrange) return;
    updateNodes(calculateAlignedNodes(getSelectionLayoutNodes(), alignment));
  }

  void distributeSelection({required bool horizontal}) {
    if (!applyDraft() || !canArrange || selectedNodes.length < 3) return;
    updateNodes(
      calculateDistributedNodes(
        getSelectionLayoutNodes(),
        horizontal: horizontal,
      ),
    );
  }

  void staggerSelection(int intervalMs) {
    if (!applyDraft()) return;
    var index = 0;
    updateNodes([
      for (final node in document.paintOrder)
        if (selectedIds.contains(node.id))
          node.copyWith(
            motionTiming: SceneMotionTiming(
              durationMs: node.motionTiming.durationMs,
              delayMs: index++ * intervalMs,
              curve: node.motionTiming.curve,
            ),
          ),
    ]);
  }

  void groupSelection() {
    if (!applyDraft() || !canGroup) return;
    final nodes = getSelectionLayoutNodes();
    final byId = {for (final node in nodes) node.id: node};
    final left = nodes.map((node) => node.rect.x).reduce(math.min);
    final top = nodes.map((node) => node.rect.y).reduce(math.min);
    final right = nodes
        .map((node) => node.rect.x + node.rect.width)
        .reduce(math.max);
    final bottom = nodes
        .map((node) => node.rect.y + node.rect.height)
        .reduce(math.max);
    final id = _getUniqueId(
      'frame',
      document.nodes.map((node) => node.id).toSet(),
    );
    final frame = SceneNode(
      id: id,
      componentId: 'frame',
      parentId: selectedNode.parentId,
      rect: SceneRect(
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      ),
      layout: const SceneLayout(),
      renderOrder: nodes.map((node) => node.renderOrder).reduce(math.max),
    );
    _updateDocument(
      document.copyWith(
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

  void ungroupSelection() {
    if (!applyDraft() || !canUngroup) return;
    final frame = selectedNode;
    final children = document.getChildren(frame.id);
    if (children.isEmpty) {
      deleteSelectedNode();
      return;
    }
    final geometry = calculateSceneLayout(
      document: document,
      size: Size(
        document.canvas.referenceWidth.toDouble(),
        document.canvas.referenceHeight.toDouble(),
      ),
    );
    final frameRect = geometry[frame.id]!.rect;
    final parentSize = getParentContentSize(frame, geometry);
    final padding = getParentLayout(frame).padding;
    final replacements = {
      for (final node in children)
        node.id: node.copyWith(
          parentId: frame.parentId,
          rect: SceneRect(
            x:
                (frameRect.left - padding + geometry[node.id]!.rect.left) /
                parentSize.width,
            y:
                (frameRect.top - padding + geometry[node.id]!.rect.top) /
                parentSize.height,
            width: geometry[node.id]!.rect.width / parentSize.width,
            height: geometry[node.id]!.rect.height / parentSize.height,
          ),
        ),
    };
    _updateDocument(
      document.copyWith(
        nodes: [
          for (final node in document.nodes)
            if (node.id != frame.id) replacements[node.id] ?? node,
        ],
      ),
      selectedId: children.last.id,
      selectedIds: children.map((node) => node.id).toSet(),
    );
  }

  String _getUniqueId(String base, Set<String> ids) {
    var id = base;
    var suffix = 2;
    while (ids.contains(id)) {
      id = '$base-${suffix++}';
    }
    ids.add(id);
    return id;
  }

  void updateScene({SceneCanvas? canvas, SceneBackground? background}) {
    if (!applyDraft()) return;
    _updateDocument(
      document.copyWith(canvas: canvas, background: background),
      selectedId: selectedId,
    );
  }

  void placeNode(SceneNode template, Offset position) {
    if (!applyDraft()) return;
    final existing = document.nodes
        .where((node) => node.id == template.id)
        .firstOrNull;
    final node = existing ?? template;
    final rect = node.rect.copyWith(
      x: position.dx.clamp(0.0, 1 - node.rect.width),
      y: position.dy.clamp(0.0, 1 - node.rect.height),
    );
    final placed = node.copyWith(parentId: null, rect: rect);
    _updateDocument(
      document.copyWith(
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

  void updateNodeText(String id, String text) {
    if (!applyDraft()) return;
    final node = document.nodes.firstWhere((node) => node.id == id);
    if (text.isEmpty) {
      inspector.showError('Text must not be empty.');
      return;
    }
    updateNode(node.copyWith(properties: {...node.properties, 'text': text}));
  }

  void updateSelectionStyle(SceneStyle style) {
    if (!applyDraft() || selectedIds.isEmpty) return;
    final token =
        selectedNode.styleToken ??
        _getUniqueId('$selectedId-style', document.styleTokens.keys.toSet());
    _updateDocument(
      document.copyWith(
        styleTokens: {...document.styleTokens, token: style},
        nodes: [
          for (final node in document.nodes)
            selectedIds.contains(node.id)
                ? node.copyWith(styleToken: token)
                : node,
        ],
      ),
      selectedId: selectedId,
    );
  }

  void previewSelectionStyle(SceneStyle style) {
    if (selectedIds.isEmpty) return;
    final token = selectedNode.styleToken ?? '$selectedId-style-preview';
    _previewDocument = document.copyWith(
      styleTokens: {...document.styleTokens, token: style},
      nodes: [
        for (final node in document.nodes)
          selectedIds.contains(node.id)
              ? node.copyWith(styleToken: token)
              : node,
      ],
    );
    notifyListeners();
  }

  void cancelPreview() {
    if (_previewDocument == null) return;
    _previewDocument = null;
    notifyListeners();
  }

  void previewBackground(SceneBackground background) {
    _previewDocument = document.copyWith(background: background);
    notifyListeners();
  }

  void createGuide(SceneGuide guide) {
    if (!applyDraft()) return;
    _updateDocument(
      document.copyWith(guides: [...document.guides, guide]),
      selectedId: selectedId,
    );
  }

  void updateGuide(int index, SceneGuide guide) {
    if (!applyDraft()) return;
    final guides = [...document.guides];
    guides[index] = guide;
    _updateDocument(document.copyWith(guides: guides), selectedId: selectedId);
  }

  void deleteGuide(int index) {
    if (!applyDraft()) return;
    final guides = [...document.guides]..removeAt(index);
    _updateDocument(document.copyWith(guides: guides), selectedId: selectedId);
  }

  void updateSelectionStyleToken(String? token) {
    if (!applyDraft() || selectedIds.isEmpty) return;
    updateNodes([
      for (final node in selectedNodes) node.copyWith(styleToken: token),
    ]);
  }

  void duplicateSelectedNode() {
    if (!applyDraft()) return;
    if (!canDuplicateNode) {
      throw StateError('Layout slots can only be added once.');
    }
    final ids = document.nodes.map((entry) => entry.id).toSet();
    final subtree = getSelectionSubtree();
    final copies = {
      for (final node in subtree) node.id: _getUniqueId('${node.id}-copy', ids),
    };
    _updateDocument(
      document.copyWith(
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

  void deleteSelectedNode() {
    if (!applyDraft()) return;
    final reason = deletionBlockReason;
    if (reason != null) throw StateError(reason);
    final ids = getSelectionSubtree().map((node) => node.id).toSet();
    final index = document.nodes.indexWhere((node) => node.id == selectedId);
    final nodes = document.nodes
        .where((node) => !ids.contains(node.id))
        .toList();
    final next = nodes[math.min(index, nodes.length - 1)].id;
    _updateDocument(
      document.copyWith(nodes: nodes),
      selectedId: next,
      selectedIds: {next},
    );
  }

  void _removeNode(String nodeId) {
    final reason = getDeletionBlockReason(nodeId);
    if (reason != null) throw StateError(reason);
    final ids = {nodeId};
    for (final node in document.layerOrder) {
      if (ids.contains(node.parentId)) ids.add(node.id);
    }
    final index = document.nodes.indexWhere((node) => node.id == nodeId);
    final nodes = document.nodes
        .where((node) => !ids.contains(node.id))
        .toList();
    _updateDocument(
      document.copyWith(nodes: nodes),
      selectedId: ids.contains(selectedId)
          ? nodes[math.min(index, nodes.length - 1)].id
          : selectedId,
      selectedIds: selectedIds.difference(ids).isEmpty
          ? {nodes[math.min(index, nodes.length - 1)].id}
          : selectedIds.difference(ids),
    );
  }

  void _updateDocument(
    SceneDocument document, {
    required String selectedId,
    Set<String>? selectedIds,
  }) {
    // The codec is the same boundary used by code generation. Invalid edits
    // never replace the last working preview or create an undo entry.
    final encoded = encodeSceneDocument(document);
    final hadPreview = _previewDocument != null;
    if (encoded == _revision.encoded) {
      _previewDocument = null;
      if (hadPreview) notifyListeners();
      return;
    }
    final updated = decodeSceneDocument(encoded);
    _componentCatalog.validateDocument(updated);
    _presetCatalog.validateDocument(updated);
    _declaredLayout?.validateDocument(updated);
    _undo.add(_revision);
    _redo.clear();
    _applyRevision((
      document: updated,
      encoded: encoded,
      selectedId: selectedId,
      selectedIds:
          selectedIds ??
          (selectedId == this.selectedId ? this.selectedIds : {selectedId}),
    ));
  }

  void _applyRevision(_SceneRevision revision) {
    _previewDocument = null;
    _revision = revision;
    inspector.resetNode(selectedNode, canvas: getInspectorCanvas());
    notifyListeners();
  }

  SceneCanvas getInspectorCanvas() {
    final geometry = calculateSceneLayout(
      document: document,
      size: Size(
        document.canvas.referenceWidth.toDouble(),
        document.canvas.referenceHeight.toDouble(),
      ),
    );
    final size = getParentContentSize(selectedNode, geometry);
    return document.canvas.copyWith(
      referenceWidth: size.width.round(),
      referenceHeight: size.height.round(),
    );
  }

  List<SceneNode> getSelectionLayoutNodes() {
    final geometry = calculateSceneLayout(
      document: document,
      size: Size(
        document.canvas.referenceWidth.toDouble(),
        document.canvas.referenceHeight.toDouble(),
      ),
    );
    final result = <SceneNode>[];
    for (final node in selectedNodes) {
      final rect = geometry[node.id]!.rect;
      final size = getParentContentSize(node, geometry);
      final padding = getParentLayout(node).padding;
      result.add(
        node.copyWith(
          rect: SceneRect(
            x: (rect.left - padding) / size.width,
            y: (rect.top - padding) / size.height,
            width: rect.width / size.width,
            height: rect.height / size.height,
          ),
        ),
      );
    }
    return result;
  }

  void undo() {
    if (!applyDraft() || !canUndo) return;
    _redo.add(_revision);
    _applyRevision(_undo.removeLast());
  }

  void redo() {
    if (!applyDraft() || !canRedo) return;
    _undo.add(_revision);
    _applyRevision(_redo.removeLast());
  }

  bool save() {
    if (!applyDraft()) return false;
    if (file.readAsStringSync() != _source) {
      throw const FileSystemException(
        'The scene changed on disk. Reload it before saving.',
      );
    }
    final encoded = _revision.encoded;
    final source = '$encoded\n';
    // A failed write must leave the authored file intact. A sibling temporary
    // file keeps the final rename on the same filesystem.
    final temporaryDirectory = file.parent.createTempSync('.akari-studio-');
    try {
      final temporary = File('${temporaryDirectory.path}/scene.json');
      temporary.writeAsStringSync(source, flush: true);
      temporary.renameSync(file.path);
    } finally {
      temporaryDirectory.deleteSync(recursive: true);
    }
    _source = source;
    _savedDocument = encoded;
    notifyListeners();
    return true;
  }

  void reload() => _loadFromDisk();

  void _loadFromDisk({bool initial = false}) {
    final source = file.readAsStringSync();
    final document = decodeSceneDocument(source);
    _componentCatalog.validateDocument(document);
    _presetCatalog.validateDocument(document);
    _declaredLayout?.validateDocument(document);
    _source = source;
    final revision = (
      document: document,
      encoded: encodeSceneDocument(document),
      selectedId:
          !initial && document.nodes.any((node) => node.id == selectedId)
          ? selectedId
          : document.nodes.first.id,
      selectedIds: {
        !initial && document.nodes.any((node) => node.id == selectedId)
            ? selectedId
            : document.nodes.first.id,
      },
    );
    _savedDocument = revision.encoded;
    _undo.clear();
    _redo.clear();
    if (initial) {
      _revision = revision;
    } else {
      _applyRevision(revision);
    }
  }

  @override
  void dispose() {
    inspector.dispose();
    super.dispose();
  }
}
