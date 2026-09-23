import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mozais_greeter_ui/mozais_greeter_ui.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'editor_controller.dart';
import 'editor_settings_scope.dart';
import 'editor_strings.dart';

/// Whether the preview shows placeholder boxes or the real greeter widgets.
enum PreviewMode { outline, real }

const _accent = Color(0xff4fc3f7);
const _boxPadding = 4.0;
const _handleRadius = 6.0;
const _rotationDotRadius = 7.0;
const _rotationDotDistance = 30.0;
const _trackballRadius = 24.0;
const _trackballDistance = 44.0;
const _dragSensitivity = 0.5;

typedef _ThemeSignature = ({
  String id,
  SceneBackgroundKind kind,
  String? asset,
  int color,
});

_ThemeSignature _sceneThemeSignature(SceneDocument document) => (
  id: document.id,
  kind: document.background.kind,
  asset: document.background.asset,
  color: document.background.color,
);

/// Renders the document with the real runtime and overlays an editing box for
/// the selected node.
class ScenePreview extends StatefulWidget {
  const ScenePreview({
    required this.controller,
    required this.feature,
    required this.mode,
    this.interacting = false,
    super.key,
  });

  final SceneEditorController controller;
  final GreeterFeature feature;
  final PreviewMode mode;

  /// When true the selection overlay is removed so the embedded greeter
  /// receives pointer events directly.
  final bool interacting;

  @override
  State<ScenePreview> createState() => _ScenePreviewState();
}

class _ScenePreviewState extends State<ScenePreview> {
  SceneDocument? _cachedDocument;
  _ThemeSignature? _themeSignature;
  int _themeRevision = 0;
  ThemeBundle? _builtTheme;
  GreeterFeature? _builtFeature;
  Set<ScenePredicate>? _cachedPredicates;
  ThemeBundle? _cachedTheme;
  Widget? _cachedOutlineScene;
  Widget? _cachedRealScene;
  SceneDocument? _outlineDocument;
  SceneDocument? _realDocument;
  Timer? _prewarmTimer;

  @override
  void dispose() {
    _prewarmTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[widget.controller.selectionListenable];
    if (widget.mode == PreviewMode.outline) {
      listenables.add(widget.controller.predicatesListenable);
    } else {
      listenables.addAll([
        widget.feature.serviceSlots,
        widget.feature.authPromptSlots,
        widget.feature.accountPickerSlots,
        widget.feature.sessionPickerSlots,
        widget.feature.powerSlots,
        widget.feature.dormantSlots,
      ]);
    }
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) => _buildPreview(context),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final document = widget.controller.document;
    if (document == null) {
      return Center(child: Text(EditorStringsScope.of(context).previewEmpty));
    }
    final aspectRatio = switch (widget.mode) {
      PreviewMode.outline => EditorSettingsScope.of(
        context,
      ).settings.previewAspectRatio,
      PreviewMode.real => View.of(context).display.size.aspectRatio,
    };
    final scene = _sceneFor(context, document);
    final theme = _cachedTheme!;
    final activePredicates = _activePredicates;
    final safeArea = document.canvas.useSafeArea
        ? MediaQuery.paddingOf(context)
        : EdgeInsets.zero;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _fit(constraints.biggest, aspectRatio);
        final origin = Offset(
          (constraints.maxWidth - size.width) / 2,
          (constraints.maxHeight - size.height) / 2,
        );
        final selected = widget.controller.selectedNode;
        final selectedVisible =
            selected != null && _isNodeVisible(selected, activePredicates);
        return Stack(
          children: [
            Positioned(
              left: origin.dx,
              top: origin.dy,
              width: size.width,
              height: size.height,
              child: Stack(
                children: [
                  Positioned.fill(child: scene),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // The overlay fills the whole preview so handles dragged outside
            // the canvas stay grabbable.
            if (!widget.interacting) ...[
              if (selected != null && selectedVisible)
                Positioned.fill(
                  child: _SelectionOverlay(
                    key: const ValueKey('selectionOverlay'),
                    canvasOrigin: origin,
                    node: selected,
                    previewSize: size,
                    safeArea: safeArea,
                    minHitTarget: theme.tokens.minHitTarget,
                    onSelectAt: (position) => _selectNodeAt(
                      position: position,
                      document: document,
                      previewSize: size,
                      safeArea: safeArea,
                      minHitTarget: theme.tokens.minHitTarget,
                      activePredicates: activePredicates,
                    ),
                    onRectChanged: (rect) => widget.controller.updateSelected(
                      (node) => node.copyWith(rect: rect),
                    ),
                    onTransformChanged: (transform) =>
                        widget.controller.updateSelected(
                          (node) => node.copyWith(transform: transform),
                        ),
                  ),
                )
              else
                // No visible selection to drag, but a click can still pick
                // the topmost node under the pointer.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) => _selectNodeAt(
                      position: details.localPosition - origin,
                      document: document,
                      previewSize: size,
                      safeArea: safeArea,
                      minHitTarget: theme.tokens.minHitTarget,
                      activePredicates: activePredicates,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Set<ScenePredicate> get _activePredicates => switch (widget.mode) {
    PreviewMode.outline => widget.controller.activePredicates,
    PreviewMode.real => activeScenePredicates(
      service: widget.feature.serviceSlots.value,
      auth: widget.feature.authPromptSlots.value,
      account: widget.feature.accountPickerSlots.value,
      session: widget.feature.sessionPickerSlots.value,
      power: widget.feature.powerSlots.value,
      dormant: widget.feature.dormantSlots.value,
    ),
  };

  bool _isNodeVisible(SceneNode node, Set<ScenePredicate> activePredicates) {
    final condition = node.visibleWhen;
    return condition == null ||
        evaluateSceneCondition(condition, activePredicates);
  }

  void _selectNodeAt({
    required Offset position,
    required SceneDocument document,
    required Size previewSize,
    required EdgeInsets safeArea,
    required double minHitTarget,
    required Set<ScenePredicate> activePredicates,
  }) {
    final id = hitTestSceneNode(
      document: document,
      position: position,
      previewSize: previewSize,
      safeArea: safeArea,
      minHitTarget: minHitTarget,
      activePredicates: activePredicates,
    );
    if (id != null) {
      widget.controller.select(id);
    }
  }

  /// Rebuilds the embedded scene only when its inputs change.
  ///
  /// A selection change leaves the scene untouched so the background, blur,
  /// and greeter widgets are not re-created while the overlay moves.
  Widget _sceneFor(BuildContext context, SceneDocument document) {
    final signature = _sceneThemeSignature(document);
    if (!identical(_cachedDocument, document)) {
      _cachedDocument = document;
      if (_cachedTheme == null || signature != _themeSignature) {
        _themeSignature = signature;
        _cachedTheme = editorTheme(document);
        unawaited(_loadTheme(document, signature, ++_themeRevision));
      } else {
        _cachedTheme = _cachedTheme!.copyWith(document: document);
      }
    }
    if (!identical(_builtTheme, _cachedTheme)) {
      _builtTheme = _cachedTheme;
      _outlineDocument = null;
      _realDocument = null;
      _cachedOutlineScene = null;
      _cachedRealScene = null;
    }
    if (!identical(_builtFeature, widget.feature)) {
      _builtFeature = widget.feature;
      _realDocument = null;
      _cachedRealScene = null;
    }
    final predicates = _activePredicates;
    if (widget.mode == PreviewMode.outline &&
        (!identical(_outlineDocument, document) ||
            !setEquals(_cachedPredicates, predicates))) {
      _cachedPredicates = {...predicates};
      _outlineDocument = document;
      _cachedOutlineScene = _buildScene(
        context,
        document,
        _cachedTheme!,
        PreviewMode.outline,
      );
    }
    if (widget.mode == PreviewMode.real &&
        !identical(_realDocument, document)) {
      _realDocument = document;
      _cachedRealScene = _buildScene(
        context,
        document,
        _cachedTheme!,
        PreviewMode.real,
      );
    }
    _schedulePrewarm(context, document, predicates);
    final outline = _cachedOutlineScene ?? const SizedBox.shrink();
    final real = _cachedRealScene ?? const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: widget.mode != PreviewMode.outline,
          child: TickerMode(
            enabled: widget.mode == PreviewMode.outline,
            child: outline,
          ),
        ),
        Offstage(
          offstage: widget.mode != PreviewMode.real,
          child: TickerMode(
            enabled: widget.mode == PreviewMode.real,
            child: real,
          ),
        ),
      ],
    );
  }

  Future<void> _loadTheme(
    SceneDocument document,
    _ThemeSignature signature,
    int revision,
  ) async {
    final seed = await editorBackgroundSeed(document);
    if (!mounted || revision != _themeRevision) {
      return;
    }
    final currentDocument = widget.controller.document;
    if (currentDocument == null ||
        _sceneThemeSignature(currentDocument) != signature) {
      return;
    }
    setState(() {
      _cachedTheme = editorTheme(currentDocument, seed: seed);
      _outlineDocument = null;
      _realDocument = null;
      _cachedOutlineScene = null;
      _cachedRealScene = null;
    });
  }

  void _schedulePrewarm(
    BuildContext context,
    SceneDocument document,
    Set<ScenePredicate> predicates,
  ) {
    final needsOutline =
        _cachedOutlineScene == null || !identical(_outlineDocument, document);
    final needsReal =
        _cachedRealScene == null || !identical(_realDocument, document);
    if (!needsOutline && !needsReal) {
      return;
    }
    _prewarmTimer?.cancel();
    _prewarmTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || !identical(_cachedDocument, document)) {
        return;
      }
      if (_cachedOutlineScene == null ||
          !identical(_outlineDocument, document)) {
        _cachedPredicates = {...predicates};
        _outlineDocument = document;
        _cachedOutlineScene = _buildScene(
          context,
          document,
          _cachedTheme!,
          PreviewMode.outline,
        );
      }
      if (_cachedRealScene == null || !identical(_realDocument, document)) {
        _realDocument = document;
        _cachedRealScene = _buildScene(
          context,
          document,
          _cachedTheme!,
          PreviewMode.real,
        );
      }
      setState(() {});
    });
  }

  Widget _buildScene(
    BuildContext context,
    SceneDocument document,
    ThemeBundle theme,
    PreviewMode mode,
  ) {
    return switch (mode) {
      PreviewMode.outline => SceneRuntime(
        document: document,
        theme: theme,
        nodeBuilder: buildPlaceholderNode,
        activePredicates: widget.controller.activePredicates,
      ),
      PreviewMode.real => Theme(
        data: theme.materialTheme,
        child: GreeterSceneAdapter(
          key: ObjectKey(widget.feature),
          feature: widget.feature,
          theme: theme,
          handleKeyboard: false,
          exitOnHandoff: false,
        ),
      ),
    };
  }
}

/// Returns the topmost visible node whose transformed rectangle contains
/// [position], or null when the point is over empty scene.
String? hitTestSceneNode({
  required SceneDocument document,
  required Offset position,
  required Size previewSize,
  required EdgeInsets safeArea,
  required double minHitTarget,
  required Set<ScenePredicate> activePredicates,
}) {
  for (final node in document.paintOrder.reversed) {
    final visibleWhen = node.visibleWhen;
    if (visibleWhen != null &&
        !evaluateSceneCondition(visibleWhen, activePredicates)) {
      continue;
    }
    final geometry = _OverlayGeometry(
      node: node,
      previewSize: previewSize,
      safeArea: safeArea,
      minHitTarget: minHitTarget,
    );
    if (geometry.contains(position)) {
      return node.id;
    }
  }
  return null;
}

Size _fit(Size available, double aspectRatio) {
  if (available.width <= 0 || available.height <= 0) {
    return const Size(160, 90);
  }
  final width = available.width;
  final height = width / aspectRatio;
  if (height <= available.height) {
    return Size(width, height);
  }
  return Size(available.height * aspectRatio, available.height);
}

/// Draws a labelled placeholder for a node so the editor preview shows layout
/// without depending on the greeter's widget catalog.
Widget buildPlaceholderNode(BuildContext context, SceneNode node) {
  final color = _kindColor(node.kind);
  return DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.22),
      border: Border.all(color: color.withValues(alpha: 0.9)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Text(
          node.id,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

Color _kindColor(SceneNodeKind kind) {
  final hue = (kind.index * 47) % 360;
  return HSLColor.fromAHSL(1, hue.toDouble(), 0.6, 0.65).toColor();
}

enum _DragRegion { none, move, resize, rotateZ, rotate3d }

/// Maps the selected node's layout rect and transform into preview space.
///
/// Local coordinates have their origin at [baseRect]'s top-left corner, which
/// is exactly what [sceneNodeTransformMatrix] expects.
class _OverlayGeometry {
  _OverlayGeometry({
    required SceneNode node,
    required Size previewSize,
    required EdgeInsets safeArea,
    required double minHitTarget,
  }) : baseRect = sceneNodeRect(
         node: node,
         sceneSize: previewSize,
         safeArea: safeArea,
         minHitTarget: minHitTarget,
       ) {
    forward = sceneNodeTransformMatrix(node.transform, baseRect.size);
    inverse = forward.determinant().abs() < 1e-9
        ? Matrix4.identity()
        : Matrix4.inverted(forward);
    availableWidth = math.max(0.0, previewSize.width - safeArea.horizontal);
    availableHeight = math.max(0.0, previewSize.height - safeArea.vertical);

    final width = baseRect.width;
    final height = baseRect.height;
    final localBox = Rect.fromLTWH(
      -_boxPadding,
      -_boxPadding,
      width + _boxPadding * 2,
      height + _boxPadding * 2,
    );
    topLeft = toScene(localBox.topLeft);
    topRight = toScene(localBox.topRight);
    bottomRight = toScene(localBox.bottomRight);
    bottomLeft = toScene(localBox.bottomLeft);
    center = toScene(Offset(width / 2, height / 2));

    final topMid = (topLeft + topRight) / 2;
    final bottomMid = (bottomLeft + bottomRight) / 2;
    rotationDot = topMid + _outward(topMid, center) * _rotationDotDistance;
    trackball = bottomMid + _outward(bottomMid, center) * _trackballDistance;
    resizeHandle = bottomRight;
  }

  final Rect baseRect;
  late final Matrix4 forward;
  late final Matrix4 inverse;
  late final double availableWidth;
  late final double availableHeight;
  late final Offset topLeft;
  late final Offset topRight;
  late final Offset bottomRight;
  late final Offset bottomLeft;
  late final Offset center;
  late final Offset rotationDot;
  late final Offset trackball;
  late final Offset resizeHandle;

  Offset toScene(Offset local) =>
      baseRect.topLeft + MatrixUtils.transformPoint(forward, local);

  Offset toLocal(Offset scene) =>
      MatrixUtils.transformPoint(inverse, scene - baseRect.topLeft);

  bool contains(Offset scene) {
    final local = toLocal(scene);
    return Rect.fromLTWH(0, 0, baseRect.width, baseRect.height).contains(local);
  }
}

Offset _outward(Offset point, Offset center) {
  final delta = point - center;
  final distance = delta.distance;
  if (distance == 0) {
    return const Offset(0, -1);
  }
  return delta / distance;
}

double _normalizeAngle(double degrees) {
  final value = degrees % 360;
  if (value >= 180) {
    return value - 360;
  }
  return value;
}

MouseCursor _cursorFor(_DragRegion region) {
  return switch (region) {
    _DragRegion.move => SystemMouseCursors.move,
    _DragRegion.resize => SystemMouseCursors.resizeUpLeftDownRight,
    _DragRegion.rotateZ || _DragRegion.rotate3d => SystemMouseCursors.grab,
    _DragRegion.none => SystemMouseCursors.basic,
  };
}

class _SelectionOverlay extends StatefulWidget {
  const _SelectionOverlay({
    required this.canvasOrigin,
    required this.node,
    required this.previewSize,
    required this.safeArea,
    required this.minHitTarget,
    required this.onSelectAt,
    required this.onRectChanged,
    required this.onTransformChanged,
    super.key,
  });

  /// The canvas's top-left corner inside the overlay's coordinate space.
  final Offset canvasOrigin;
  final SceneNode node;
  final Size previewSize;
  final EdgeInsets safeArea;
  final double minHitTarget;
  final ValueChanged<Offset> onSelectAt;
  final ValueChanged<SceneRect> onRectChanged;
  final ValueChanged<SceneTransform> onTransformChanged;

  @override
  State<_SelectionOverlay> createState() => _SelectionOverlayState();
}

class _SelectionOverlayState extends State<_SelectionOverlay> {
  _DragRegion _hoverRegion = _DragRegion.none;
  _DragRegion _pressRegion = _DragRegion.none;
  _DragRegion _activeRegion = _DragRegion.none;

  Offset _pressPointer = Offset.zero;
  _OverlayGeometry? _startGeometry;
  Offset _startPointer = Offset.zero;
  SceneRect _startRect = const SceneRect(x: 0, y: 0, width: 1, height: 1);
  SceneTransform _startTransform = const SceneTransform();
  Offset _startCenter = Offset.zero;
  double _startAngle = 0;
  SceneRect? _liveRect;
  SceneTransform? _liveTransform;

  _OverlayGeometry get _geometry => _OverlayGeometry(
    node: widget.node.copyWith(rect: _liveRect, transform: _liveTransform),
    previewSize: widget.previewSize,
    safeArea: widget.safeArea,
    minHitTarget: widget.minHitTarget,
  );

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry;
    return MouseRegion(
      cursor: _cursorFor(_hoverRegion),
      onHover: (event) =>
          _updateHover(_toCanvas(event.localPosition), geometry),
      onExit: (_) => _setHover(_DragRegion.none),
      child: Listener(
        onPointerDown: (event) {
          final position = _toCanvas(event.localPosition);
          _pressRegion = _regionAt(position, geometry);
          _pressPointer = position;
        },
        onPointerUp: (_) => _pressRegion = _DragRegion.none,
        onPointerCancel: (_) => _pressRegion = _DragRegion.none,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) =>
              widget.onSelectAt(_toCanvas(details.localPosition)),
          onPanStart: (_) => _handlePanStart(geometry),
          onPanUpdate: (details) =>
              _handlePanUpdate(_toCanvas(details.localPosition)),
          onPanEnd: (_) => _handlePanEnd(),
          onPanCancel: _handlePanEnd,
          child: CustomPaint(
            painter: _SelectionPainter(
              geometry: geometry,
              canvasOrigin: widget.canvasOrigin,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  Offset _toCanvas(Offset position) => position - widget.canvasOrigin;

  _DragRegion _regionAt(Offset position, _OverlayGeometry geometry) {
    if ((position - geometry.rotationDot).distance <= _rotationDotRadius + 6) {
      return _DragRegion.rotateZ;
    }
    if ((position - geometry.trackball).distance <= _trackballRadius) {
      return _DragRegion.rotate3d;
    }
    if ((position - geometry.resizeHandle).distance <= _handleRadius + 6) {
      return _DragRegion.resize;
    }
    if (geometry.contains(position)) {
      return _DragRegion.move;
    }
    return _DragRegion.none;
  }

  void _updateHover(Offset position, _OverlayGeometry geometry) {
    if (_activeRegion != _DragRegion.none) {
      return;
    }
    _setHover(_regionAt(position, geometry));
  }

  void _setHover(_DragRegion region) {
    if (region == _hoverRegion) {
      return;
    }
    setState(() => _hoverRegion = region);
  }

  void _handlePanStart(_OverlayGeometry geometry) {
    if (_pressRegion == _DragRegion.none) {
      return;
    }
    _activeRegion = _pressRegion;
    _startGeometry = geometry;
    _startPointer = _pressPointer;
    _startRect = widget.node.rect;
    _startTransform = widget.node.transform;
    _liveRect = _startRect;
    _liveTransform = _startTransform;
    _startCenter = geometry.center;
    final delta = _pressPointer - geometry.center;
    _startAngle = math.atan2(delta.dy, delta.dx);
  }

  void _handlePanUpdate(Offset position) {
    final geometry = _startGeometry;
    if (geometry == null) {
      return;
    }
    switch (_activeRegion) {
      case _DragRegion.move:
        _applyMove(geometry, position - _startPointer);
      case _DragRegion.resize:
        _applyResize(geometry, position);
      case _DragRegion.rotateZ:
        _applyRotateZ(position);
      case _DragRegion.rotate3d:
        _applyRotate3d(position - _startPointer);
      case _DragRegion.none:
        break;
    }
  }

  void _handlePanEnd() {
    if (_activeRegion == _DragRegion.none) {
      return;
    }
    final rect = _liveRect;
    final transform = _liveTransform;
    if (rect != null && rect != _startRect) {
      widget.onRectChanged(rect);
    }
    if (transform != null && transform != _startTransform) {
      widget.onTransformChanged(transform);
    }
    _activeRegion = _DragRegion.none;
    _pressRegion = _DragRegion.none;
    _startGeometry = null;
    setState(() {
      _liveRect = null;
      _liveTransform = null;
    });
  }

  void _applyMove(_OverlayGeometry geometry, Offset delta) {
    if (geometry.availableWidth <= 0 || geometry.availableHeight <= 0) {
      return;
    }
    final dx = delta.dx / geometry.availableWidth;
    final dy = delta.dy / geometry.availableHeight;
    _setLiveRect(
      _startRect.copyWith(
        x: (_startRect.x + dx).clamp(0.0, 1.0 - _startRect.width),
        y: (_startRect.y + dy).clamp(0.0, 1.0 - _startRect.height),
      ),
    );
  }

  void _applyResize(_OverlayGeometry geometry, Offset position) {
    if (geometry.availableWidth <= 0 || geometry.availableHeight <= 0) {
      return;
    }
    final localDelta =
        geometry.toLocal(position) - geometry.toLocal(_startPointer);
    final startWidth = geometry.availableWidth * _startRect.width;
    final startHeight = geometry.availableHeight * _startRect.height;
    final maxWidth = 1.0 - _startRect.x;
    final maxHeight = 1.0 - _startRect.y;
    _setLiveRect(
      _startRect.copyWith(
        width: ((startWidth + localDelta.dx) / geometry.availableWidth)
            .clamp(math.min(0.02, maxWidth), maxWidth)
            .toDouble(),
        height: ((startHeight + localDelta.dy) / geometry.availableHeight)
            .clamp(math.min(0.02, maxHeight), maxHeight)
            .toDouble(),
      ),
    );
  }

  void _applyRotateZ(Offset position) {
    final delta = position - _startCenter;
    final angle = math.atan2(delta.dy, delta.dx);
    final degrees = (angle - _startAngle) * 180 / math.pi;
    _setLiveTransform(
      _startTransform.copyWith(
        rotationZ: _normalizeAngle(_startTransform.rotationZ + degrees),
      ),
    );
  }

  void _applyRotate3d(Offset delta) {
    _setLiveTransform(
      _startTransform.copyWith(
        rotationY: _normalizeAngle(
          _startTransform.rotationY + delta.dx * _dragSensitivity,
        ),
        rotationX: _normalizeAngle(
          _startTransform.rotationX - delta.dy * _dragSensitivity,
        ),
      ),
    );
  }

  void _setLiveRect(SceneRect rect) {
    if (rect == _liveRect) {
      return;
    }
    setState(() => _liveRect = rect);
  }

  void _setLiveTransform(SceneTransform transform) {
    if (transform == _liveTransform) {
      return;
    }
    setState(() => _liveTransform = transform);
  }
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter({required this.geometry, required this.canvasOrigin});

  final _OverlayGeometry geometry;
  final Offset canvasOrigin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(canvasOrigin.dx, canvasOrigin.dy);
    final outline = Paint()
      ..color = _accent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    _drawDashedLine(canvas, geometry.topLeft, geometry.topRight, outline);
    _drawDashedLine(canvas, geometry.topRight, geometry.bottomRight, outline);
    _drawDashedLine(canvas, geometry.bottomRight, geometry.bottomLeft, outline);
    _drawDashedLine(canvas, geometry.bottomLeft, geometry.topLeft, outline);

    final fill = Paint()..color = _accent;
    final rim = Paint()
      ..color = Colors.black54
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(geometry.resizeHandle, _handleRadius, fill);
    canvas.drawCircle(geometry.resizeHandle, _handleRadius, rim);

    canvas.drawLine(
      (geometry.topLeft + geometry.topRight) / 2,
      geometry.rotationDot,
      Paint()
        ..color = _accent.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(geometry.rotationDot, _rotationDotRadius, fill);
    canvas.drawCircle(geometry.rotationDot, _rotationDotRadius, rim);

    canvas.drawCircle(
      geometry.trackball,
      _trackballRadius,
      Paint()..color = _accent.withValues(alpha: 0.2),
    );
    canvas.drawCircle(
      geometry.trackball,
      _trackballRadius,
      Paint()
        ..color = _accent.withValues(alpha: 0.8)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: geometry.trackball,
        radius: _trackballRadius * 0.6,
      ),
      math.pi * 0.15,
      math.pi * 0.7,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) {
    if (canvasOrigin != oldDelegate.canvasOrigin) {
      return true;
    }
    return geometry.baseRect != oldDelegate.geometry.baseRect ||
        geometry.topLeft != oldDelegate.geometry.topLeft ||
        geometry.topRight != oldDelegate.geometry.topRight ||
        geometry.bottomRight != oldDelegate.geometry.bottomRight ||
        geometry.bottomLeft != oldDelegate.geometry.bottomLeft ||
        geometry.rotationDot != oldDelegate.geometry.rotationDot ||
        geometry.trackball != oldDelegate.geometry.trackball ||
        geometry.resizeHandle != oldDelegate.geometry.resizeHandle;
  }
}

void _drawDashedLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  double dash = 5,
  double gap = 4,
}) {
  final total = (b - a).distance;
  if (total == 0) {
    return;
  }
  final direction = (b - a) / total;
  var distance = 0.0;
  while (distance < total) {
    final start = a + direction * distance;
    final end = a + direction * math.min(distance + dash, total);
    canvas.drawLine(start, end, paint);
    distance += dash + gap;
  }
}
