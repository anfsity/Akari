import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'editor_controller.dart';
import 'editor_settings_scope.dart';
import 'editor_strings.dart';

const _accent = Color(0xff4fc3f7);
const _boxPadding = 4.0;
const _handleRadius = 6.0;
const _rotationDotRadius = 7.0;
const _rotationDotDistance = 30.0;
const _trackballRadius = 24.0;
const _trackballDistance = 44.0;
const _dragSensitivity = 0.5;

/// Renders the document with the real runtime and overlays an editing box for
/// the selected node.
class ScenePreview extends StatelessWidget {
  const ScenePreview({required this.controller, super.key});

  final SceneEditorController controller;

  @override
  Widget build(BuildContext context) {
    final document = controller.document;
    if (document == null) {
      return Center(child: Text(EditorStringsScope.of(context).previewEmpty));
    }
    final aspectRatio = EditorSettingsScope.of(
      context,
    ).settings.previewAspectRatio;
    final theme = editorTheme(document);
    final safeArea = document.canvas.useSafeArea
        ? MediaQuery.paddingOf(context)
        : EdgeInsets.zero;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _fit(constraints.biggest, aspectRatio);
        final selected = controller.selectedNode;
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SceneRuntime(
                    document: document,
                    theme: theme,
                    nodeBuilder: buildPlaceholderNode,
                    activePredicates: controller.activePredicates,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                  ),
                ),
                if (selected != null)
                  Positioned.fill(
                    child: _SelectionOverlay(
                      node: selected,
                      previewSize: size,
                      safeArea: safeArea,
                      minHitTarget: theme.tokens.minHitTarget,
                      onRectChanged: (rect) => controller.updateSelected(
                        (node) => node.copyWith(rect: rect),
                      ),
                      onTransformChanged: (transform) =>
                          controller.updateSelected(
                            (node) => node.copyWith(transform: transform),
                          ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
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
    required this.node,
    required this.previewSize,
    required this.safeArea,
    required this.minHitTarget,
    required this.onRectChanged,
    required this.onTransformChanged,
  });

  final SceneNode node;
  final Size previewSize;
  final EdgeInsets safeArea;
  final double minHitTarget;
  final ValueChanged<SceneRect> onRectChanged;
  final ValueChanged<SceneTransform> onTransformChanged;

  @override
  State<_SelectionOverlay> createState() => _SelectionOverlayState();
}

class _SelectionOverlayState extends State<_SelectionOverlay> {
  _DragRegion _hoverRegion = _DragRegion.none;
  _DragRegion _activeRegion = _DragRegion.none;

  _OverlayGeometry? _startGeometry;
  Offset _startPointer = Offset.zero;
  SceneRect _startRect = const SceneRect(x: 0, y: 0, width: 1, height: 1);
  SceneTransform _startTransform = const SceneTransform();
  Offset _startCenter = Offset.zero;
  double _startAngle = 0;

  _OverlayGeometry get _geometry => _OverlayGeometry(
    node: widget.node,
    previewSize: widget.previewSize,
    safeArea: widget.safeArea,
    minHitTarget: widget.minHitTarget,
  );

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry;
    return MouseRegion(
      cursor: _cursorFor(_hoverRegion),
      onHover: (event) => _updateHover(event.localPosition, geometry),
      onExit: (_) => _setHover(_DragRegion.none),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) =>
            _handlePanStart(details.localPosition, geometry),
        onPanUpdate: (details) => _handlePanUpdate(details.localPosition),
        onPanEnd: (_) => _handlePanEnd(),
        onPanCancel: _handlePanEnd,
        child: CustomPaint(
          painter: _SelectionPainter(geometry: geometry),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  _DragRegion _regionAt(Offset position, _OverlayGeometry geometry) {
    if ((position - geometry.rotationDot).distance <=
        _rotationDotRadius + 6) {
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

  void _handlePanStart(Offset position, _OverlayGeometry geometry) {
    final region = _regionAt(position, geometry);
    if (region == _DragRegion.none) {
      return;
    }
    _activeRegion = region;
    _startGeometry = geometry;
    _startPointer = position;
    _startRect = widget.node.rect;
    _startTransform = widget.node.transform;
    _startCenter = geometry.center;
    final delta = position - geometry.center;
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
    _activeRegion = _DragRegion.none;
    _startGeometry = null;
  }

  void _applyMove(_OverlayGeometry geometry, Offset delta) {
    if (geometry.availableWidth <= 0 || geometry.availableHeight <= 0) {
      return;
    }
    final dx = delta.dx / geometry.availableWidth;
    final dy = delta.dy / geometry.availableHeight;
    widget.onRectChanged(
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
    final localDelta = geometry.toLocal(position) -
        geometry.toLocal(_startPointer);
    final startWidth = geometry.availableWidth * _startRect.width;
    final startHeight = geometry.availableHeight * _startRect.height;
    widget.onRectChanged(
      _startRect.copyWith(
        width: ((startWidth + localDelta.dx) / geometry.availableWidth).clamp(
          0.02,
          1.0 - _startRect.x,
        ),
        height: ((startHeight + localDelta.dy) / geometry.availableHeight).clamp(
          0.02,
          1.0 - _startRect.y,
        ),
      ),
    );
  }

  void _applyRotateZ(Offset position) {
    final delta = position - _startCenter;
    final angle = math.atan2(delta.dy, delta.dx);
    final degrees = (angle - _startAngle) * 180 / math.pi;
    widget.onTransformChanged(
      _startTransform.copyWith(
        rotationZ: _normalizeAngle(_startTransform.rotationZ + degrees),
      ),
    );
  }

  void _applyRotate3d(Offset delta) {
    widget.onTransformChanged(
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
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter({required this.geometry});

  final _OverlayGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
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
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) => true;
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
