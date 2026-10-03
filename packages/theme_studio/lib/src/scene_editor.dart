import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:scene/scene.dart';

/// Owns one authoring session. Only validated documents enter history, and
/// saving refuses to replace a file modified outside this session.
class SceneEditor extends ChangeNotifier {
  SceneEditor(this.file) {
    _source = file.readAsStringSync();
    _document = decodeSceneDocument(_source);
    _savedDocument = encodeSceneDocument(_document);
    _selectedId = _document.nodes.first.id;
  }

  final File file;
  late String _source;
  late String _savedDocument;
  late SceneDocument _document;
  late String _selectedId;
  final _undo = <({SceneDocument document, String selectedId})>[];
  final _redo = <({SceneDocument document, String selectedId})>[];

  SceneDocument get document => _document;
  String get selectedId => _selectedId;
  SceneNode get selectedNode =>
      _document.nodes.firstWhere((node) => node.id == _selectedId);
  bool get isDirty => encodeSceneDocument(_document) != _savedDocument;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get canDeleteNode => _document.nodes.length > 1;

  void selectNode(String id) {
    _document.nodes.firstWhere((node) => node.id == id);
    _selectedId = id;
    notifyListeners();
  }

  void updateNode(SceneNode node) {
    final index = _document.nodes.indexWhere((entry) => entry.id == node.id);
    if (index < 0) throw ArgumentError.value(node.id, 'node.id');
    final nodes = [..._document.nodes];
    nodes[index] = node;
    _updateDocument(_document.copyWith(nodes: nodes), selectedId: _selectedId);
  }

  void updateScene({SceneCanvas? canvas, SceneBackground? background}) {
    _updateDocument(
      _document.copyWith(canvas: canvas, background: background),
      selectedId: _selectedId,
    );
  }

  void duplicateSelectedNode() {
    final node = selectedNode;
    final ids = _document.nodes.map((entry) => entry.id).toSet();
    var id = '${node.id}-copy';
    var suffix = 2;
    while (ids.contains(id)) {
      id = '${node.id}-copy-${suffix++}';
    }
    final nodes = [..._document.nodes];
    nodes.insert(nodes.indexOf(node) + 1, node.copyWith(id: id));
    _updateDocument(_document.copyWith(nodes: nodes), selectedId: id);
  }

  void deleteSelectedNode() {
    if (!canDeleteNode) {
      throw StateError('A scene must contain at least one node.');
    }
    final nodes = [..._document.nodes];
    final index = nodes.indexWhere((node) => node.id == _selectedId);
    nodes.removeAt(index);
    _updateDocument(
      _document.copyWith(nodes: nodes),
      selectedId: nodes[index < nodes.length ? index : index - 1].id,
    );
  }

  void _updateDocument(SceneDocument document, {required String selectedId}) {
    // The codec is the same boundary used by code generation. Invalid edits
    // never replace the last working preview or create an undo entry.
    final updated = decodeSceneDocument(encodeSceneDocument(document));
    if (encodeSceneDocument(updated) == encodeSceneDocument(_document)) return;
    _undo.add((document: _document, selectedId: _selectedId));
    _redo.clear();
    _document = updated;
    _selectedId = selectedId;
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add((document: _document, selectedId: _selectedId));
    final previous = _undo.removeLast();
    _document = previous.document;
    _selectedId = previous.selectedId;
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add((document: _document, selectedId: _selectedId));
    final next = _redo.removeLast();
    _document = next.document;
    _selectedId = next.selectedId;
    notifyListeners();
  }

  void save() {
    if (file.readAsStringSync() != _source) {
      throw const FileSystemException(
        'The scene changed on disk. Reload it before saving.',
      );
    }
    final encoded = encodeSceneDocument(_document);
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
  }

  void reload() {
    final source = file.readAsStringSync();
    final document = decodeSceneDocument(source);
    _source = source;
    _document = document;
    _savedDocument = encodeSceneDocument(document);
    if (!document.nodes.any((node) => node.id == _selectedId)) {
      _selectedId = document.nodes.first.id;
    }
    _undo.clear();
    _redo.clear();
    notifyListeners();
  }
}
