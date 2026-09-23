import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mozais_greeter_ui/mozais_greeter_ui.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'editor_status.dart';
import 'repo_root.dart';

/// Holds the document under edit and the editor's selection and preview state.
class SceneEditorController extends ChangeNotifier {
  SceneEditorController([this._assetsDirectory]);

  final Directory? _assetsDirectory;
  SceneDocument? _document;
  String _path = '';
  String? _selectedNodeId;
  EditorStatus _status = EditorStatus.idle;
  bool _dirty = false;
  final Set<ScenePredicate> _activePredicates = <ScenePredicate>{};

  SceneDocument? get document => _document;
  String get path => _path;
  String? get selectedNodeId => _selectedNodeId;
  EditorStatus get status => _status;
  bool get dirty => _dirty;
  Set<ScenePredicate> get activePredicates => _activePredicates;

  SceneNode? get selectedNode {
    final document = _document;
    final id = _selectedNodeId;
    if (document == null || id == null) {
      return null;
    }
    for (final node in document.nodes) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }

  void setPath(String path) {
    _path = path;
    notifyListeners();
  }

  Future<bool> open() async {
    if (_path.isEmpty) {
      _status = const EditorStatus(EditorStatusKind.enterPathFirst);
      notifyListeners();
      return false;
    }
    try {
      final source = await File(_path).readAsString();
      final document = decodeSceneDocument(source);
      _document = document;
      _selectedNodeId = document.nodes.first.id;
      _dirty = false;
      _status = EditorStatus(EditorStatusKind.opened, _path);
      notifyListeners();
      return true;
    } on Object catch (error) {
      _status = EditorStatus(EditorStatusKind.openFailed, error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> save() async {
    final document = _document;
    if (document == null || _path.isEmpty) {
      return false;
    }
    try {
      await File(_path).writeAsString(encodeSceneDocument(document));
      _dirty = false;
      _status = EditorStatus(EditorStatusKind.saved, _path);
      notifyListeners();
      return true;
    } on Object catch (error) {
      _status = EditorStatus(EditorStatusKind.saveFailed, error);
      notifyListeners();
      return false;
    }
  }

  void select(String id) {
    _selectedNodeId = id;
    notifyListeners();
  }

  /// Applies a document-level edit such as the canvas or background.
  void updateDocument(SceneDocument Function(SceneDocument document) update) {
    final document = _document;
    if (document == null) {
      return;
    }
    _document = update(document);
    _dirty = true;
    notifyListeners();
  }

  /// Copies [source] into the repository assets and points the background at it.
  ///
  /// Image and video files become their matching [SceneBackgroundKind]; the
  /// runtime has no video renderer yet, so a video background falls back to
  /// solid until one exists.
  Future<bool> importBackgroundAsset(File source) async {
    if (_document == null) {
      return false;
    }
    final directory = _assetsDirectory ?? repoAssetsDirectory();
    if (directory == null) {
      _status = EditorStatus(
        EditorStatusKind.backgroundImportFailed,
        const FileSystemException('Repository assets directory not found.'),
      );
      notifyListeners();
      return false;
    }
    try {
      directory.createSync(recursive: true);
      final name = _uniqueAssetName(
        directory,
        source.path.split(Platform.pathSeparator).last,
      );
      await source.copy('${directory.path}/$name');
      final asset = 'assets/$name';
      _status = EditorStatus(EditorStatusKind.backgroundImported, asset);
      updateDocument(
        (document) => document.copyWith(
          background: document.background.copyWith(
            kind: _backgroundKindFor(name),
            asset: asset,
          ),
        ),
      );
      return true;
    } on Object catch (error) {
      _status = EditorStatus(EditorStatusKind.backgroundImportFailed, error);
      notifyListeners();
      return false;
    }
  }

  void updateSelected(SceneNode Function(SceneNode node) update) {
    final document = _document;
    final node = selectedNode;
    if (document == null || node == null) {
      return;
    }
    final updated = update(node);
    _document = document.copyWith(
      nodes: [
        for (final candidate in document.nodes)
          if (candidate.id == node.id) updated else candidate,
      ],
    );
    _dirty = true;
    notifyListeners();
  }

  void addNode() {
    final document = _document;
    if (document == null) {
      return;
    }
    final id = _uniqueNodeId(document, 'node');
    final node = SceneNode(
      id: id,
      kind: SceneNodeKind.decoration,
      rect: const SceneRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
    );
    _document = document.copyWith(nodes: [...document.nodes, node]);
    _selectedNodeId = id;
    _dirty = true;
    notifyListeners();
  }

  void duplicateSelected() {
    final document = _document;
    final node = selectedNode;
    if (document == null || node == null) {
      return;
    }
    final id = _uniqueNodeId(document, '${node.id}_copy');
    final copy = node.copyWith(
      id: id,
      rect: node.rect.copyWith(
        x: (node.rect.x + 0.02).clamp(0, 1 - node.rect.width),
        y: (node.rect.y + 0.02).clamp(0, 1 - node.rect.height),
      ),
    );
    _document = document.copyWith(nodes: [...document.nodes, copy]);
    _selectedNodeId = id;
    _dirty = true;
    notifyListeners();
  }

  void deleteSelected() {
    final document = _document;
    final node = selectedNode;
    if (document == null || node == null) {
      return;
    }
    // A scene document must keep at least one node.
    final nodes = [
      for (final candidate in document.nodes)
        if (candidate.id != node.id) candidate,
    ];
    if (nodes.isEmpty) {
      _status = const EditorStatus(EditorStatusKind.keepOneNode);
      notifyListeners();
      return;
    }
    _document = document.copyWith(nodes: nodes);
    _selectedNodeId = nodes.first.id;
    _dirty = true;
    notifyListeners();
  }

  void togglePredicate(ScenePredicate predicate) {
    if (!_activePredicates.remove(predicate)) {
      _activePredicates.add(predicate);
    }
    notifyListeners();
  }
}

String _uniqueNodeId(SceneDocument document, String base) {
  final ids = {for (final node in document.nodes) node.id};
  var index = 1;
  while (ids.contains('$base$index')) {
    index++;
  }
  return '$base$index';
}

const _videoExtensions = {'mp4', 'webm', 'mkv', 'mov', 'avi', 'm4v'};

SceneBackgroundKind _backgroundKindFor(String name) {
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return _videoExtensions.contains(extension)
      ? SceneBackgroundKind.video
      : SceneBackgroundKind.image;
}

/// Keeps an imported file from overwriting an existing asset of the same name.
String _uniqueAssetName(Directory directory, String name) {
  if (!File('${directory.path}/$name').existsSync()) {
    return name;
  }
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final extension = dot > 0 ? name.substring(dot) : '';
  var index = 2;
  while (File('${directory.path}/$base-$index$extension').existsSync()) {
    index++;
  }
  return '$base-$index$extension';
}

/// Theme used only to drive the editor preview.
///
/// The palette is document-independent, so it is built once; each call only
/// swaps in the document under edit. Resolves background assets from the
/// repository root because the editor does not bundle them.
final ThemeBundle _editorThemeBase = buildDefaultTheme().copyWith(
  backgrounds: {
    SceneBackgroundKind.solid: const SolidBackgroundRenderer(),
    SceneBackgroundKind.image: ImageBackgroundRenderer(
      resolveImage: (asset) {
        final file = repoAssetFile(asset);
        return file == null ? AssetImage(asset) : FileImage(file);
      },
    ),
  },
);

ThemeBundle editorTheme(SceneDocument document) =>
    _editorThemeBase.copyWith(document: document);
