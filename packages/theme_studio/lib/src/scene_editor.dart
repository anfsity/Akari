import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'node_inspector_controller.dart';

// Store canonical JSON with history so status queries and undo/redo do not
// serialize the entire scene again. Selection changes reuse the same encoding.
typedef _SceneRevision = ({
  SceneDocument document,
  String encoded,
  String selectedId,
});

/// Owns one authoring session. Only validated documents enter history, and
/// saving refuses to replace a file modified outside this session.
class SceneEditor extends ChangeNotifier {
  SceneEditor(
    this.file, {
    this._componentCatalog = const ThemeComponentCatalog(),
    ThemeLayoutDefinition? layout,
  }) : _declaredLayout = layout {
    _loadFromDisk(initial: true);
    inspector = NodeInspectorController(selectedNode, document.canvas);
  }

  final File file;
  ThemeComponentCatalog _componentCatalog;
  ThemeLayoutDefinition? _declaredLayout;
  late final NodeInspectorController inspector;
  late String _source;
  late String _savedDocument;
  late _SceneRevision _revision;
  final _undo = <_SceneRevision>[];
  final _redo = <_SceneRevision>[];

  SceneDocument get document => _revision.document;
  String get encodedDocument => _revision.encoded;
  String get selectedId => _revision.selectedId;
  SceneNode get selectedNode =>
      document.nodes.firstWhere((node) => node.id == selectedId);
  bool get isDirty => _revision.encoded != _savedDocument;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get canDeleteNode => deletionBlockReason == null;
  bool get canDuplicateNode => layout?.findSlot(selectedId) == null;
  String? get deletionBlockReason => getDeletionBlockReason(selectedId);
  ThemeComponentCatalog get componentCatalog => _componentCatalog;
  ThemeLayoutDefinition? get layout =>
      _declaredLayout?.sceneId == document.id ? _declaredLayout : null;
  List<ThemeLayoutSlot> get missingRequiredSlots =>
      layout?.findMissingRequiredSlots(document) ?? const [];

  void updateAuthoring({
    required ThemeComponentCatalog componentCatalog,
    required ThemeLayoutDefinition? layout,
  }) {
    if (identical(componentCatalog, _componentCatalog) &&
        identical(layout, _declaredLayout)) {
      return;
    }
    // Undo and redo trust the revision invariant too. New authoring rules must
    // accept history before replacing this session's catalog and layout.
    for (final revision in [_revision, ..._undo, ..._redo]) {
      componentCatalog.validateDocument(revision.document);
      layout?.validateDocument(revision.document);
    }
    _componentCatalog = componentCatalog;
    _declaredLayout = layout;
    notifyListeners();
  }

  String? getDeletionBlockReason(String nodeId) {
    if (document.nodes.length == 1) return 'A scene needs at least one node.';
    final slot = layout?.findSlot(nodeId);
    if (slot != null && slot.isRequired) {
      return '${slot.label} is required by this layout.';
    }
    return null;
  }

  void updateLayoutSlot(String nodeId, {required bool isPresent}) {
    if (!applyDraft()) return;
    final slot = layout?.findSlot(nodeId);
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

  bool selectNode(String id) {
    if (!applyDraft()) return false;
    if (!document.nodes.any((node) => node.id == id)) {
      throw ArgumentError.value(id, 'id');
    }
    if (selectedId == id) return true;
    _applyRevision((
      document: document,
      encoded: _revision.encoded,
      selectedId: id,
    ));
    return true;
  }

  void updateNode(SceneNode node) {
    final index = document.nodes.indexWhere((entry) => entry.id == node.id);
    if (index < 0) throw ArgumentError.value(node.id, 'node.id');
    final nodes = [...document.nodes];
    nodes[index] = node;
    _updateDocument(document.copyWith(nodes: nodes), selectedId: selectedId);
  }

  void updateScene({SceneCanvas? canvas, SceneBackground? background}) {
    if (!applyDraft()) return;
    _updateDocument(
      document.copyWith(canvas: canvas, background: background),
      selectedId: selectedId,
    );
  }

  void duplicateSelectedNode() {
    if (!applyDraft()) return;
    if (!canDuplicateNode) {
      throw StateError('Layout slots can only be added once.');
    }
    final node = selectedNode;
    final ids = document.nodes.map((entry) => entry.id).toSet();
    var id = '${node.id}-copy';
    var suffix = 2;
    while (ids.contains(id)) {
      id = '${node.id}-copy-${suffix++}';
    }
    final nodes = [...document.nodes];
    nodes.insert(nodes.indexOf(node) + 1, node.copyWith(id: id));
    _updateDocument(document.copyWith(nodes: nodes), selectedId: id);
  }

  void deleteSelectedNode() {
    if (!applyDraft()) return;
    _removeNode(selectedId);
  }

  void _removeNode(String nodeId) {
    final reason = getDeletionBlockReason(nodeId);
    if (reason != null) throw StateError(reason);
    final nodes = [...document.nodes];
    final index = nodes.indexWhere((node) => node.id == nodeId);
    nodes.removeAt(index);
    _updateDocument(
      document.copyWith(nodes: nodes),
      selectedId: selectedId == nodeId
          ? nodes[index < nodes.length ? index : index - 1].id
          : selectedId,
    );
  }

  void _updateDocument(SceneDocument document, {required String selectedId}) {
    // The codec is the same boundary used by code generation. Invalid edits
    // never replace the last working preview or create an undo entry.
    final encoded = encodeSceneDocument(document);
    if (encoded == _revision.encoded) return;
    final updated = decodeSceneDocument(encoded);
    _componentCatalog.validateDocument(updated);
    _declaredLayout?.validateDocument(updated);
    _undo.add(_revision);
    _redo.clear();
    _applyRevision((
      document: updated,
      encoded: encoded,
      selectedId: selectedId,
    ));
  }

  void _applyRevision(_SceneRevision revision) {
    _revision = revision;
    inspector.resetNode(selectedNode, canvas: document.canvas);
    notifyListeners();
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
    _declaredLayout?.validateDocument(document);
    _source = source;
    final revision = (
      document: document,
      encoded: encodeSceneDocument(document),
      selectedId:
          !initial && document.nodes.any((node) => node.id == selectedId)
          ? selectedId
          : document.nodes.first.id,
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
