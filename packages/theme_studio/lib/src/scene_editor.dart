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
  final _undo = <SceneDocument>[];
  final _redo = <SceneDocument>[];

  SceneDocument get document => _document;
  String get selectedId => _selectedId;
  SceneNode get selectedNode =>
      _document.nodes.firstWhere((node) => node.id == _selectedId);
  bool get isDirty => encodeSceneDocument(_document) != _savedDocument;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

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
    // The codec is the same boundary used by code generation. Invalid edits
    // never replace the last working preview or create an undo entry.
    final updated = decodeSceneDocument(
      encodeSceneDocument(_document.copyWith(nodes: nodes)),
    );
    if (encodeSceneDocument(updated) == encodeSceneDocument(_document)) return;
    _undo.add(_document);
    _redo.clear();
    _document = updated;
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(_document);
    _document = _undo.removeLast();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_document);
    _document = _redo.removeLast();
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
