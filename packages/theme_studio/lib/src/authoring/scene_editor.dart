import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../model/node_geometry.dart';
import '../resources/confined_path.dart';
import 'node_inspector_controller.dart';
import 'scene_tree_operations.dart';
import 'studio_components.dart';

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
    this._minHitTarget = 44,
    this._safeArea = EdgeInsets.zero,
    Map<String, String> fontFamilies = const {},
  }) : _declaredLayout = layout,
       _fontFamilies = Map.unmodifiable(fontFamilies) {
    _loadFromDisk(initial: true);
    inspector = NodeInspectorController(selectedNode, getInspectorCanvas());
  }

  final File file;
  ThemeComponentCatalog _componentCatalog;
  ThemePresetCatalog _presetCatalog;
  ThemeLayoutDefinition? _declaredLayout;
  double _minHitTarget;
  EdgeInsets _safeArea;
  Map<String, String> _fontFamilies;
  late final NodeInspectorController inspector;
  late String _source;
  late String _savedDocument;
  late _SceneRevision _revision;
  final _undo = <_SceneRevision>[];
  final _redo = <_SceneRevision>[];
  SceneDocument? _previewDocument;
  bool _disposed = false;

  bool get isDisposed => _disposed;
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
      selectedNode.transitions.isEmpty &&
      selectedNode.tracks.isEmpty &&
      selectedNode.breakpoints.isEmpty &&
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
    double? minHitTarget,
    EdgeInsets? safeArea,
    Map<String, String>? fontFamilies,
  }) {
    final nextMinHitTarget = minHitTarget ?? _minHitTarget;
    final nextSafeArea = safeArea ?? _safeArea;
    final nextFontFamilies = fontFamilies == null
        ? _fontFamilies
        : Map<String, String>.unmodifiable(fontFamilies);
    if (identical(componentCatalog, _componentCatalog) &&
        identical(presetCatalog, _presetCatalog) &&
        identical(layout, _declaredLayout) &&
        nextMinHitTarget == _minHitTarget &&
        nextSafeArea == _safeArea &&
        mapEquals(nextFontFamilies, _fontFamilies)) {
      return;
    }
    // Undo and redo trust the revision invariant too. New authoring rules must
    // accept history before replacing this session's catalog and layout.
    for (final revision in [_revision, ..._undo, ..._redo]) {
      _validateWith(revision.document, componentCatalog, presetCatalog, layout);
    }
    _componentCatalog = componentCatalog;
    _presetCatalog = presetCatalog;
    _declaredLayout = layout;
    _minHitTarget = nextMinHitTarget;
    _safeArea = nextSafeArea;
    _fontFamilies = nextFontFamilies;
    notifyListeners();
  }

  void updateThemeProperty(String name, String value) {
    if (!tryApplyDraft()) return;
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
    final ids = getDescendantIds(document, [nodeId]);
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
    if (!tryApplyDraft()) return;
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
    if (!tryApplyDraft()) return;
    final layout = this.layout;
    if (layout == null) throw StateError('This scene has no layout.');
    _updateDocument(
      layout.getDocumentWithPreset(document, presetId),
      selectedId: selectedId,
    );
  }

  void addRequiredLayoutSlots() {
    if (!tryApplyDraft()) return;
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

  /// Validates and commits any pending inspector draft into scene history,
  /// surfacing validation errors in [inspector] and returning whether the caller
  /// may proceed cleanly.
  bool tryApplyDraft() {
    if (!inspector.hasDraft && inspector.error == null) return true;
    try {
      updateNode(inspector.getUpdatedNode());
      if (inspector.hasDraft || inspector.error != null) {
        inspector.resetNode(selectedNode, canvas: getInspectorCanvas());
      }
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
    if (!tryApplyDraft()) return false;
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

  SceneLayout getParentLayout(SceneNode node) =>
      getParentSceneLayout(document, node);

  List<SceneNode> getSelectionRoots() =>
      getSceneSelectionRoots(document, selectedNodes, selectedIds);

  Map<String, SceneNodeGeometry> _calculateReferenceGeometry() =>
      calculateSceneLayout(
        document: document,
        size: getSceneReferenceSize(document),
        safeArea: _safeArea,
        fontFamilies: _fontFamilies,
        minHitTarget: _minHitTarget,
      );

  List<SceneNode> getSelectionSubtree() {
    final ids = getDescendantIds(document, selectedIds);
    return document.nodes.where((node) => ids.contains(node.id)).toList();
  }

  void moveSelection(Offset delta) {
    if (!tryApplyDraft()) return;
    final geometry = _calculateReferenceGeometry();
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
  ) => getSceneParentContentSize(document, node, geometry, _safeArea);

  void alignSelection(NodeAlignment alignment) {
    if (!tryApplyDraft() || !canArrange) return;
    updateNodes(calculateAlignedNodes(getSelectionLayoutNodes(), alignment));
  }

  void distributeSelection({required bool horizontal}) {
    if (!tryApplyDraft() || !canArrange || selectedNodes.length < 3) return;
    updateNodes(
      calculateDistributedNodes(
        getSelectionLayoutNodes(),
        horizontal: horizontal,
      ),
    );
  }

  void staggerSelection(int intervalMs) {
    if (!tryApplyDraft()) return;
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

  void _applyMutation(SceneMutationResult result) {
    _updateDocument(
      result.document,
      selectedId: result.selectedId,
      selectedIds: result.selectedIds,
    );
  }

  void groupSelection() {
    if (!tryApplyDraft() || !canGroup) return;
    _applyMutation(
      buildGroupedDocument(
        document: document,
        parentId: selectedNode.parentId,
        layoutNodes: getSelectionLayoutNodes(),
        selectedIds: selectedIds,
        reservedIds: getReservedSceneIds(document, layout),
      ),
    );
  }

  void ungroupSelection() {
    if (!tryApplyDraft() || !canUngroup) return;
    final frame = selectedNode;
    final children = document.getChildren(frame.id);
    if (children.isEmpty) {
      deleteSelectedNode();
      return;
    }
    _applyMutation(
      buildUngroupedDocument(
        document: document,
        frame: frame,
        children: children,
        geometry: _calculateReferenceGeometry(),
        safeArea: _safeArea,
      ),
    );
  }

  static void _validateWith(
    SceneDocument document,
    ThemeComponentCatalog componentCatalog,
    ThemePresetCatalog presetCatalog,
    ThemeLayoutDefinition? layout,
  ) {
    componentCatalog.validateDocument(document);
    presetCatalog.validateDocument(document);
    layout?.validateDocument(document);
  }

  ({SceneDocument document, String encoded}) _validateDocument(
    SceneDocument document,
  ) {
    final encoded = encodeSceneDocument(document);
    final updated = decodeSceneDocument(encoded);
    _validateWith(updated, _componentCatalog, _presetCatalog, _declaredLayout);
    return (document: updated, encoded: encoded);
  }

  /// Validates a prospective scene canvas/background change against the schema,
  /// catalogs, and declared layout before side effects like importing assets.
  void validateScene({SceneCanvas? canvas, SceneBackground? background}) {
    _validateDocument(
      document.copyWith(canvas: canvas, background: background),
    );
  }

  void updateScene({SceneCanvas? canvas, SceneBackground? background}) {
    if (!tryApplyDraft()) return;
    _updateDocument(
      document.copyWith(canvas: canvas, background: background),
      selectedId: selectedId,
    );
  }

  void placeNode(SceneNode template, Offset position) {
    if (!tryApplyDraft()) return;
    _applyMutation(
      buildPlacedNodeDocument(
        document: document,
        template: template,
        position: position,
      ),
    );
  }

  bool updateNodeText(String id, String text) {
    if (!tryApplyDraft()) return false;
    final node = document.nodes.firstWhere((node) => node.id == id);
    if (text.isEmpty) {
      inspector.showError('Text must not be empty.');
      return false;
    }
    updateNode(node.copyWith(properties: {...node.properties, 'text': text}));
    return true;
  }

  void createComponent(
    StudioComponent component, {
    Offset position = const Offset(.3, .3),
  }) {
    if (!tryApplyDraft()) return;
    _applyMutation(
      buildCreatedComponentDocument(
        document: document,
        component: component,
        position: position,
        reservedIds: getReservedSceneIds(document, layout),
      ),
    );
  }

  void createAssetNode(SceneAsset asset) {
    if (!tryApplyDraft()) return;
    _applyMutation(
      buildCreatedAssetDocument(
        document: document,
        asset: asset,
        reservedIds: getReservedSceneIds(document, layout),
      ),
    );
  }

  String? getLayerMoveBlockReason(String id, String? parentId) =>
      getSceneLayerMoveBlockReason(document, id, parentId);

  void moveLayer(String id, {required String? parentId, String? beforeId}) {
    if (!tryApplyDraft()) return;
    final reason = getLayerMoveBlockReason(id, parentId);
    if (reason != null) {
      inspector.showError(reason);
      return;
    }
    _applyMutation(
      buildMovedLayerDocument(
        document: document,
        id: id,
        parentId: parentId,
        beforeId: beforeId,
        calculateGeometry: _calculateReferenceGeometry,
        safeArea: _safeArea,
      ),
    );
  }

  void updateSelectionStyle(SceneStyle style) {
    if (!tryApplyDraft() || selectedIds.isEmpty) return;
    final token =
        selectedNode.styleToken ??
        allocateSceneId('$selectedId-style', document.styleTokens.keys.toSet());
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
    final token =
        selectedNode.styleToken ??
        allocateSceneId(
          '$selectedId-style-preview',
          document.styleTokens.keys.toSet(),
        );
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

  void previewNode(SceneNode node) {
    _previewDocument = document.copyWith(
      nodes: [
        for (final current in document.nodes)
          current.id == node.id ? node : current,
      ],
    );
    notifyListeners();
  }

  void previewBackground(SceneBackground background) {
    _previewDocument = document.copyWith(background: background);
    notifyListeners();
  }

  void createGuide(SceneGuide guide) {
    if (!tryApplyDraft()) return;
    _updateDocument(
      document.copyWith(guides: [...document.guides, guide]),
      selectedId: selectedId,
    );
  }

  void updateGuide(int index, SceneGuide guide) {
    if (!tryApplyDraft()) return;
    final guides = [...document.guides];
    guides[index] = guide;
    _updateDocument(document.copyWith(guides: guides), selectedId: selectedId);
  }

  void deleteGuide(int index) {
    if (!tryApplyDraft()) return;
    final guides = [...document.guides]..removeAt(index);
    _updateDocument(document.copyWith(guides: guides), selectedId: selectedId);
  }

  void updateSelectionStyleToken(String? token) {
    if (!tryApplyDraft() || selectedIds.isEmpty) return;
    updateNodes([
      for (final node in selectedNodes) node.copyWith(styleToken: token),
    ]);
  }

  void duplicateSelectedNode() {
    if (!tryApplyDraft()) return;
    if (!canDuplicateNode) {
      throw StateError('Layout slots can only be added once.');
    }
    _applyMutation(
      buildDuplicatedSelectionDocument(
        document: document,
        subtree: getSelectionSubtree(),
        selectedId: selectedId,
        selectedIds: selectedIds,
        reservedIds: getReservedSceneIds(document, layout),
      ),
    );
  }

  void deleteSelectedNode() {
    if (!tryApplyDraft()) return;
    final reason = deletionBlockReason;
    if (reason != null) throw StateError(reason);
    _applyMutation(
      buildRemovedNodesDocument(
        document: document,
        removedIds: getSelectionSubtree().map((node) => node.id).toSet(),
        primaryTargetId: selectedId,
        currentSelectedId: selectedId,
        currentSelectedIds: selectedIds,
        collapseSelectionToNext: true,
      ),
    );
  }

  void _removeNode(String nodeId) {
    final reason = getDeletionBlockReason(nodeId);
    if (reason != null) throw StateError(reason);
    _applyMutation(
      buildRemovedNodesDocument(
        document: document,
        removedIds: getDescendantIds(document, [nodeId]),
        primaryTargetId: nodeId,
        currentSelectedId: selectedId,
        currentSelectedIds: selectedIds,
        collapseSelectionToNext: false,
      ),
    );
  }

  void _updateDocument(
    SceneDocument document, {
    required String selectedId,
    Set<String>? selectedIds,
  }) {
    // The codec is the same boundary used by code generation. Invalid edits
    // never replace the last working preview or create an undo entry.
    final validated = _validateDocument(document);
    final hadPreview = _previewDocument != null;
    if (validated.encoded == _revision.encoded) {
      _previewDocument = null;
      if (hadPreview) notifyListeners();
      return;
    }
    _undo.add(_revision);
    _redo.clear();
    _applyRevision((
      document: validated.document,
      encoded: validated.encoded,
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
    final geometry = _calculateReferenceGeometry();
    final size = getParentContentSize(selectedNode, geometry);
    return document.canvas.copyWith(
      referenceWidth: size.width.round(),
      referenceHeight: size.height.round(),
    );
  }

  Size getNodePixelSize(SceneNode node) {
    final geometry = _calculateReferenceGeometry()[node.id];
    if (geometry != null) return geometry.rect.size;
    return Size(
      node.rect.width * document.canvas.referenceWidth,
      node.rect.height * document.canvas.referenceHeight,
    );
  }

  List<SceneNode> getSelectionLayoutNodes() => getSceneSelectionLayoutNodes(
    document,
    selectedNodes,
    _calculateReferenceGeometry(),
    _safeArea,
  );

  void undo() {
    if (!tryApplyDraft() || !canUndo) return;
    _redo.add(_revision);
    _applyRevision(_undo.removeLast());
  }

  void redo() {
    if (!tryApplyDraft() || !canRedo) return;
    _undo.add(_revision);
    _applyRevision(_redo.removeLast());
  }

  bool save() {
    if (!tryApplyDraft()) return false;
    if (file.readAsStringSync() != _source) {
      throw const FileSystemException(
        'The scene changed on disk. Reload it before saving.',
      );
    }
    final encoded = _revision.encoded;
    final source = '$encoded\n';
    writeFileAtomically(file, source, tempName: 'scene.json');
    _source = source;
    _savedDocument = encoded;
    notifyListeners();
    return true;
  }

  void reload() => _loadFromDisk();

  void _loadFromDisk({bool initial = false}) {
    final source = file.readAsStringSync();
    final document = decodeSceneDocument(source);
    _validateWith(document, _componentCatalog, _presetCatalog, _declaredLayout);
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
    _disposed = true;
    inspector.dispose();
    super.dispose();
  }
}
