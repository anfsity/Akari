import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:scene/scene.dart';

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
  SceneEditor(this.file) {
    _source = file.readAsStringSync();
    final document = decodeSceneDocument(_source);
    _revision = (
      document: document,
      encoded: encodeSceneDocument(document),
      selectedId: document.nodes.first.id,
    );
    _savedDocument = _revision.encoded;
    inspector = NodeInspectorController(selectedNode, document.canvas);
  }

  final File file;
  late final NodeInspectorController inspector;
  late String _source;
  late String _savedDocument;
  late _SceneRevision _revision;
  final _undo = <_SceneRevision>[];
  final _redo = <_SceneRevision>[];

  SceneDocument get document => _revision.document;
  String get selectedId => _revision.selectedId;
  SceneNode get selectedNode =>
      document.nodes.firstWhere((node) => node.id == selectedId);
  bool get isDirty => _revision.encoded != _savedDocument;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get canDeleteNode => document.nodes.length > 1;

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
    document.nodes.firstWhere((node) => node.id == id);
    if (selectedId == id) return true;
    _revision = (
      document: document,
      encoded: _revision.encoded,
      selectedId: id,
    );
    inspector.resetNode(selectedNode, canvas: document.canvas);
    notifyListeners();
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
    if (!canDeleteNode) {
      throw StateError('A scene must contain at least one node.');
    }
    final nodes = [...document.nodes];
    final index = nodes.indexWhere((node) => node.id == selectedId);
    nodes.removeAt(index);
    _updateDocument(
      document.copyWith(nodes: nodes),
      selectedId: nodes[index < nodes.length ? index : index - 1].id,
    );
  }

  void _updateDocument(SceneDocument document, {required String selectedId}) {
    // The codec is the same boundary used by code generation. Invalid edits
    // never replace the last working preview or create an undo entry.
    final updated = decodeSceneDocument(encodeSceneDocument(document));
    final encoded = encodeSceneDocument(updated);
    if (encoded == _revision.encoded) return;
    _undo.add(_revision);
    _redo.clear();
    _revision = (document: updated, encoded: encoded, selectedId: selectedId);
    inspector.resetNode(selectedNode, canvas: document.canvas);
    notifyListeners();
  }

  void undo() {
    if (!applyDraft() || !canUndo) return;
    _redo.add(_revision);
    _revision = _undo.removeLast();
    inspector.resetNode(selectedNode, canvas: document.canvas);
    notifyListeners();
  }

  void redo() {
    if (!applyDraft() || !canRedo) return;
    _undo.add(_revision);
    _revision = _redo.removeLast();
    inspector.resetNode(selectedNode, canvas: document.canvas);
    notifyListeners();
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
    final temporaryDirectory = file.parent.createTempSync('.mozais-studio-');
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

  void reload() {
    final source = file.readAsStringSync();
    final document = decodeSceneDocument(source);
    _source = source;
    _revision = (
      document: document,
      encoded: encodeSceneDocument(document),
      selectedId: document.nodes.any((node) => node.id == selectedId)
          ? selectedId
          : document.nodes.first.id,
    );
    _savedDocument = _revision.encoded;
    _undo.clear();
    _redo.clear();
    inspector.resetNode(selectedNode, canvas: document.canvas);
    notifyListeners();
  }

  @override
  void dispose() {
    inspector.dispose();
    super.dispose();
  }
}
