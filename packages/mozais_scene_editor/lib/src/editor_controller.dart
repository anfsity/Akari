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
  String? _documentPath;
  String? _selectedNodeId;
  EditorStatus _status = EditorStatus.idle;
  bool _dirty = false;
  bool _opening = false;
  bool _saving = false;
  bool _disposed = false;
  int _documentRevision = 0;
  int _documentGeneration = 0;
  final Set<ScenePredicate> _activePredicates = <ScenePredicate>{};

  final ValueNotifier<SceneDocument?> _documentNotifier = ValueNotifier(null);
  final ValueNotifier<int> _nodesNotifier = ValueNotifier(0);
  final ValueNotifier<String?> _selectionNotifier = ValueNotifier(null);
  final ValueNotifier<Set<ScenePredicate>> _predicatesNotifier =
      ValueNotifier(const {});
  final ValueNotifier<EditorStatus> _statusNotifier =
      ValueNotifier(EditorStatus.idle);
  final ValueNotifier<bool> _dirtyNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _openingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _savingNotifier = ValueNotifier(false);

  SceneDocument? get document => _document;
  String get path => _path;
  String? get selectedNodeId => _selectedNodeId;
  EditorStatus get status => _status;
  bool get dirty => _dirty;
  bool get opening => _opening;
  bool get saving => _saving;
  Set<ScenePredicate> get activePredicates => _activePredicates;

  /// Notifies when the document under edit changes.
  Listenable get documentListenable => _documentNotifier;

  /// Notifies when the node list's displayed ids, kinds, or order change.
  Listenable get nodesListenable => _nodesNotifier;

  /// Notifies when the selected node changes.
  Listenable get selectionListenable => _selectionNotifier;

  /// Notifies when the active predicate set changes.
  Listenable get predicatesListenable => _predicatesNotifier;

  /// Notifies when the status text or dirty flag changes.
  Listenable get statusListenable =>
      Listenable.merge([_statusNotifier, _dirtyNotifier]);

  Listenable get operationListenable =>
      Listenable.merge([_openingNotifier, _savingNotifier]);

  @override
  void dispose() {
    _disposed = true;
    _documentNotifier.dispose();
    _nodesNotifier.dispose();
    _selectionNotifier.dispose();
    _predicatesNotifier.dispose();
    _statusNotifier.dispose();
    _dirtyNotifier.dispose();
    _openingNotifier.dispose();
    _savingNotifier.dispose();
    super.dispose();
  }

  void _setDocument(SceneDocument document) {
    final previous = _document;
    _document = document;
    _documentRevision++;
    _documentNotifier.value = document;
    if (_nodesChanged(previous, document)) {
      _nodesNotifier.value++;
    }
  }

  void _setSelection(String? id) {
    _selectedNodeId = id;
    _selectionNotifier.value = id;
  }

  void _setDirty(bool value) {
    if (_dirty == value) {
      return;
    }
    _dirty = value;
    _dirtyNotifier.value = value;
  }

  void _setStatus(EditorStatus status) {
    _status = status;
    _statusNotifier.value = status;
  }

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

  Future<bool> open([String? requestedPath]) async {
    if (_opening || _saving) {
      return false;
    }
    final path = requestedPath ?? _path;
    if (path.isEmpty) {
      _setStatus(const EditorStatus(EditorStatusKind.enterPathFirst));
      notifyListeners();
      return false;
    }
    _opening = true;
    _openingNotifier.value = true;
    try {
      final source = await File(path).readAsString();
      if (_disposed) {
        return false;
      }
      final document = decodeSceneDocument(source);
      _setDocument(document);
      _path = path;
      _documentPath = path;
      _documentGeneration++;
      _setSelection(document.nodes.first.id);
      _setDirty(false);
      _setStatus(EditorStatus(EditorStatusKind.opened, path));
      notifyListeners();
      return true;
    } on Object catch (error) {
      if (_disposed) {
        return false;
      }
      if (_document != null && _documentPath != null) {
        _path = _documentPath!;
      }
      _setStatus(EditorStatus(EditorStatusKind.openFailed, error));
      notifyListeners();
      return false;
    } finally {
      if (!_disposed) {
        _opening = false;
        _openingNotifier.value = false;
      }
    }
  }

  Future<bool> save() async {
    final document = _document;
    final path = _path;
    if (document == null || path.isEmpty || _opening || _saving) {
      return false;
    }
    final revision = _documentRevision;
    final generation = _documentGeneration;
    _saving = true;
    _savingNotifier.value = true;
    try {
      await File(path).writeAsString(encodeSceneDocument(document));
      if (_disposed) {
        return true;
      }
      if (_documentGeneration == generation) {
        _documentPath = path;
        if (_documentRevision == revision) {
          _setDirty(false);
        }
        _setStatus(EditorStatus(EditorStatusKind.saved, path));
        notifyListeners();
      }
      return true;
    } on Object catch (error) {
      if (!_disposed && _documentGeneration == generation) {
        _setStatus(EditorStatus(EditorStatusKind.saveFailed, error));
        notifyListeners();
      }
      return false;
    } finally {
      if (!_disposed) {
        _saving = false;
        _savingNotifier.value = false;
      }
    }
  }

  void select(String id) {
    _setSelection(id);
    notifyListeners();
  }

  /// Applies a document-level edit such as the canvas or background.
  void updateDocument(SceneDocument Function(SceneDocument document) update) {
    final document = _document;
    if (document == null) {
      return;
    }
    _setDocument(update(document));
    _setDirty(true);
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
      _setStatus(
        EditorStatus(
          EditorStatusKind.backgroundImportFailed,
          const FileSystemException('Repository assets directory not found.'),
        ),
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
      _setStatus(EditorStatus(EditorStatusKind.backgroundImported, asset));
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
      _setStatus(EditorStatus(EditorStatusKind.backgroundImportFailed, error));
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
    _setDocument(
      document.copyWith(
        nodes: [
          for (final candidate in document.nodes)
            if (candidate.id == node.id) updated else candidate,
        ],
      ),
    );
    if (updated.id != node.id) {
      _setSelection(updated.id);
    }
    _setDirty(true);
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
    _setDocument(document.copyWith(nodes: [...document.nodes, node]));
    _setSelection(id);
    _setDirty(true);
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
    _setDocument(document.copyWith(nodes: [...document.nodes, copy]));
    _setSelection(id);
    _setDirty(true);
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
      _setStatus(const EditorStatus(EditorStatusKind.keepOneNode));
      notifyListeners();
      return;
    }
    _setDocument(document.copyWith(nodes: nodes));
    _setSelection(nodes.first.id);
    _setDirty(true);
    notifyListeners();
  }

  void togglePredicate(ScenePredicate predicate) {
    if (!_activePredicates.remove(predicate)) {
      _activePredicates.add(predicate);
    }
    _predicatesNotifier.value = {..._activePredicates};
    notifyListeners();
  }
}

bool _nodesChanged(SceneDocument? previous, SceneDocument next) {
  if (previous == null) {
    return true;
  }
  final before = previous.paintOrder;
  final after = next.paintOrder;
  if (before.length != after.length) {
    return true;
  }
  for (var i = 0; i < before.length; i++) {
    if (before[i].id != after[i].id || before[i].kind != after[i].kind) {
      return true;
    }
  }
  return false;
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
