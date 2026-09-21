import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'editor_status.dart';

/// Locates the bundled default scene by walking up from the working directory.
///
/// The editor is run from inside its package, so the repository root is a few
/// levels above it rather than a fixed relative path.
String? defaultScenePath() {
  var directory = Directory.current;
  for (var depth = 0; depth < 8; depth++) {
    final candidate = File(
      '${directory.path}/lib/themes/default/default.scene.json',
    );
    if (candidate.existsSync()) {
      return candidate.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }
  return null;
}

/// Holds the document under edit and the editor's selection and preview state.
class SceneEditorController extends ChangeNotifier {
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

/// Theme used only to drive the editor preview.
ThemeBundle editorTheme(SceneDocument document) {
  const surface = Color(0xff2a2d28);
  return ThemeBundle(
    id: 'editor',
    tokens: ThemeTokens(
      materialTheme: ThemeData.dark(),
      panelRadius: 16,
      mediumMotion: const Duration(milliseconds: 260),
      standardCurve: Curves.easeOutCubic,
      minHitTarget: 44,
      allowBlur: false,
      blurSigma: 0,
      glassColor: surface.withValues(alpha: 0.72),
      surfaceColor: surface,
      surfaceVariantColor: const Color(0xff3a3e36),
    ),
    document: document,
    backgrounds: const {
      SceneBackgroundKind.solid: SolidBackgroundRenderer(),
    },
    motions: const {
      SceneMotionPreset.fade: FadeMotionBuilder(),
      SceneMotionPreset.fadeSlide: FadeSlideMotionBuilder(),
      SceneMotionPreset.fadeScale: FadeScaleMotionBuilder(),
      SceneMotionPreset.hoverLift: HoverLiftMotionBuilder(),
      SceneMotionPreset.focusGlow: FocusGlowMotionBuilder(),
    },
  );
}
