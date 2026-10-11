import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'node_geometry.dart';
import 'studio_preferences.dart';
import 'studio_preview_host.dart';
import 'studio_viewport.dart';

enum StudioCanvasTool {
  move('Move', 'Drag to move', 'V'),
  scale('Scale', 'Drag horizontally / vertically to scale X / Y', 'K'),
  rotate('Rotate', 'Drag horizontally to rotate Z', 'R'),
  rotate3d(
    '3D rotate',
    'Drag horizontally / vertically to rotate Y / X',
    'Shift+R',
  );

  const StudioCanvasTool(this.label, this.hint, this.shortcut);

  final String label;
  final String hint;
  final String shortcut;
}

/// Renders the compiled theme at its authored resolution. Selection wraps each
/// component inside SceneRuntime so hit testing follows its actual transform,
/// paint order and visibility instead of a second approximation of layout.
class StudioPreview extends StatefulWidget {
  const StudioPreview({
    required this.theme,
    required this.document,
    required this.selectedId,
    required this.dormant,
    required this.onSelect,
    required this.onStartDrag,
    required this.onCommitDrag,
    required this.onDragNodeChanged,
    required this.preferences,
    required this.tool,
    this.lockAspectRatio = false,
    this.zoom,
    this.panEnabled = false,
    this.resetView = 0,
    this.onZoom,
    super.key,
  });

  final ThemeDefinition theme;
  final SceneDocument document;
  final String selectedId;
  final bool dormant;
  final StudioPreferences preferences;
  final StudioCanvasTool tool;
  final bool lockAspectRatio;
  final double? zoom;
  final bool panEnabled;
  final int resetView;
  final ValueChanged<double>? onZoom;
  final ValueChanged<String> onSelect;
  final SceneNode? Function(String id) onStartDrag;
  final ValueChanged<SceneNode> onCommitDrag;
  final ValueChanged<SceneNode> onDragNodeChanged;

  @override
  State<StudioPreview> createState() => _StudioPreviewState();
}

class _StudioPreviewState extends State<StudioPreview> {
  final _canvas = GlobalKey();
  _NodeDrag? _drag;

  void _startDrag(
    String id,
    DragStartDetails details, {
    NodeResizeHandle? handle,
  }) {
    final node = widget.onStartDrag(id);
    if (node == null) return;
    final canvas = _canvas.currentContext?.findRenderObject();
    if (canvas is! RenderBox) return;
    setState(() {
      _drag = _NodeDrag(
        source: node,
        canvas: canvas,
        start: canvas.globalToLocal(details.globalPosition),
        tool: widget.tool,
        handle: handle,
      );
    });
  }

  void _updateDrag(DragUpdateDetails details) {
    final drag = _drag;
    if (drag == null) return;
    final updated = drag.calculateNode(
      details.globalPosition,
      lockAspectRatio:
          widget.lockAspectRatio || HardwareKeyboard.instance.isShiftPressed,
      minHitTarget: widget.theme.bundle.tokens.minHitTarget,
      gridSize: widget.preferences.snapToGrid
          ? widget.preferences.gridSize.toDouble()
          : null,
    );
    if (!drag.hasGeometryChange(updated)) return;
    setState(() => drag.preview = updated);
    widget.onDragNodeChanged(updated);
  }

  void _stopDrag({required bool commit}) {
    final drag = _drag;
    if (drag == null) return;
    if (!commit) widget.onDragNodeChanged(drag.source);
    setState(() => _drag = null);
    if (commit) widget.onCommitDrag(drag.preview);
  }

  final _simulation = StudioPreviewHost();

  late GreeterThemeComponents _components;

  @override
  void initState() {
    super.initState();
    _updateComponents();
  }

  @override
  void didUpdateWidget(StudioPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.theme, widget.theme)) {
      _updateComponents();
    }
  }

  void _updateComponents() {
    _components = widget.theme.components(
      GreeterThemeContext(host: _simulation.host, tokens: widget.theme.tokens),
    );
  }

  @override
  void dispose() {
    _simulation.dispose();
    super.dispose();
  }

  SceneDocument _getPreviewDocument() {
    final dragged = _drag?.preview;
    if (dragged == null) return widget.document;
    return widget.document.copyWith(
      nodes: [
        for (final node in widget.document.nodes)
          if (node.id == dragged.id) dragged else node,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = _getPreviewDocument();
    final referenceSize = Size(
      document.canvas.referenceWidth.toDouble(),
      document.canvas.referenceHeight.toDouble(),
    );
    final selected = document.nodes.firstWhere(
      (node) => node.id == widget.selectedId,
    );
    final predicates = _getPreviewPredicates(widget.dormant);
    final visible =
        selected.visibleWhen == null ||
        evaluateSceneCondition(selected.visibleWhen!, predicates);
    return StudioViewport(
      canvasKey: _canvas,
      referenceSize: referenceSize,
      zoom: widget.zoom,
      resetView: widget.resetView,
      panEnabled: widget.panEnabled,
      onZoom: (zoom) => widget.onZoom?.call(zoom),
      childBuilder: (viewportScale) => CustomPaint(
        foregroundPainter: widget.preferences.showGrid
            ? _GridPainter(widget.preferences.gridSize)
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PreviewScene(
              theme: widget.theme,
              document: document,
              referenceSize: referenceSize,
              dormant: widget.dormant,
              nodeBuilder: _buildInteractiveNode,
            ),
            if (visible)
              _NodeSelectionOverlay(
                node: selected,
                canvasSize: referenceSize,
                viewportScale: viewportScale,
                minHitTarget: widget.theme.bundle.tokens.minHitTarget,
                showHandles: widget.tool == StudioCanvasTool.move,
                onStart: (handle, details) =>
                    _startDrag(selected.id, details, handle: handle),
                onUpdate: _updateDrag,
                onStop: (_) => _stopDrag(commit: true),
                onCancel: () => _stopDrag(commit: false),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveNode(BuildContext context, SceneNode node) =>
      _PreviewNode(
        nodeId: node.id,
        onSelect: () => widget.onSelect(node.id),
        onStartDrag: (details) => _startDrag(node.id, details),
        onUpdateDrag: _updateDrag,
        onStopDrag: (_) => _stopDrag(commit: true),
        onCancelDrag: () => _stopDrag(commit: false),
        child: _components.build(context, node),
      );
}

/// One gesture owns its source and transient result together. Calculations
/// always use the gesture's source, while notifications compare the last result.
class _NodeDrag {
  _NodeDrag({
    required this.source,
    required this.canvas,
    required this.start,
    required this.tool,
    this.handle,
  }) : preview = source;

  final SceneNode source;
  final RenderBox canvas;
  final Offset start;
  final StudioCanvasTool tool;
  final NodeResizeHandle? handle;
  SceneNode preview;

  SceneNode calculateNode(
    Offset globalPosition, {
    required bool lockAspectRatio,
    required double minHitTarget,
    double? gridSize,
  }) {
    // Convert through the canvas so node transforms and viewport zoom do not
    // change the direction or speed of the pointer's movement.
    final delta = canvas.globalToLocal(globalPosition) - start;
    if (handle case final handle?) {
      return calculateResizedNode(
        source: source,
        canvasSize: canvas.size,
        handle: handle,
        delta: delta,
        lockAspectRatio: lockAspectRatio,
        minHitTarget: minHitTarget,
        gridSize: gridSize,
      );
    }
    return switch (tool) {
      StudioCanvasTool.move => source.copyWith(
        rect: calculateMovedRect(
          rect: source.rect,
          canvasSize: canvas.size,
          delta: delta,
          gridSize: gridSize,
        ),
      ),
      StudioCanvasTool.scale => source.copyWith(
        transform: source.transform.copyWith(
          scaleX: _calculateScale(
            source.transform.scaleX,
            delta.dx / canvas.size.width,
          ),
          scaleY: _calculateScale(
            source.transform.scaleY,
            delta.dy / canvas.size.height,
          ),
        ),
      ),
      StudioCanvasTool.rotate => source.copyWith(
        transform: source.transform.copyWith(
          rotationZ:
              source.transform.rotationZ + 360 * delta.dx / canvas.size.width,
        ),
      ),
      StudioCanvasTool.rotate3d => source.copyWith(
        transform: source.transform.copyWith(
          rotationX:
              source.transform.rotationX - 180 * delta.dy / canvas.size.height,
          rotationY:
              source.transform.rotationY + 180 * delta.dx / canvas.size.width,
        ),
      ),
    };
  }

  bool hasGeometryChange(SceneNode node) =>
      node.rect.x != preview.rect.x ||
      node.rect.y != preview.rect.y ||
      node.rect.width != preview.rect.width ||
      node.rect.height != preview.rect.height ||
      node.transform.scaleX != preview.transform.scaleX ||
      node.transform.scaleY != preview.transform.scaleY ||
      node.transform.rotationX != preview.transform.rotationX ||
      node.transform.rotationY != preview.transform.rotationY ||
      node.transform.rotationZ != preview.transform.rotationZ;

  // Retain mirrored axes and keep scale usable at the canvas edge. Scaling
  // changes the transform, while resizing changes the component's layout rect.
  double _calculateScale(double source, double delta) =>
      (source < 0 ? -1 : 1) * (source.abs() + delta * 3).clamp(0.01, 100.0);
}

/// Material and localization belong to the compiled theme preview. Editor
/// controls keep using shadcn; reduced motion keeps authoring hit tests stable.
class _PreviewScene extends StatelessWidget {
  const _PreviewScene({
    required this.theme,
    required this.document,
    required this.referenceSize,
    required this.dormant,
    required this.nodeBuilder,
  });

  final ThemeDefinition theme;
  final SceneDocument document;
  final bool dormant;
  final SceneNodeBuilder nodeBuilder;
  final Size referenceSize;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme.materialTheme,
    home: MediaQuery(
      data: MediaQueryData(size: referenceSize, disableAnimations: true),
      child: Scaffold(
        body: SceneRuntime(
          document: document,
          theme: theme.bundle,
          backgroundBlurSigma: AlwaysStoppedAnimation(
            dormant ? 0 : document.background.blurSigma,
          ),
          activePredicates: _getPreviewPredicates(dormant),
          nodeBuilder: nodeBuilder,
        ),
      ),
    ),
  );
}

class _PreviewNode extends StatelessWidget {
  const _PreviewNode({
    required this.nodeId,
    required this.onSelect,
    required this.onStartDrag,
    required this.onUpdateDrag,
    required this.onStopDrag,
    required this.onCancelDrag,
    required this.child,
  });

  final String nodeId;
  final VoidCallback onSelect;
  final GestureDragStartCallback onStartDrag;
  final GestureDragUpdateCallback onUpdateDrag;
  final GestureDragEndCallback onStopDrag;
  final GestureDragCancelCallback onCancelDrag;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    // Flutter reports an accepted pan's pointer cancellation as onPanEnd.
    // Clear the draft first so a cancelled pointer cannot commit a move.
    onPointerCancel: (_) => onCancelDrag(),
    child: GestureDetector(
      key: ValueKey('preview-$nodeId'),
      behavior: HitTestBehavior.opaque,
      onTap: onSelect,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: onStartDrag,
      onPanUpdate: onUpdateDrag,
      onPanEnd: onStopDrag,
      onPanCancel: onCancelDrag,
      child: ExcludeFocus(child: IgnorePointer(child: child)),
    ),
  );
}

Set<ScenePredicate> _getPreviewPredicates(bool dormant) => {
  ScenePredicate.isServiceReady,
  ScenePredicate.isAuthPrompting,
  ScenePredicate.hasSelectedUser,
  ScenePredicate.isSessionReady,
  if (dormant) ScenePredicate.isDormant,
};

/// Selection belongs to the canvas, outside the component's paint transform.
/// Handles keep their screen size and remain usable on small or scaled nodes.
class _NodeSelectionOverlay extends StatelessWidget {
  const _NodeSelectionOverlay({
    required this.node,
    required this.canvasSize,
    required this.viewportScale,
    required this.minHitTarget,
    required this.showHandles,
    required this.onStart,
    required this.onUpdate,
    required this.onStop,
    required this.onCancel,
  });

  final SceneNode node;
  final Size canvasSize;
  final double viewportScale;
  final double minHitTarget;
  final bool showHandles;
  final void Function(NodeResizeHandle, DragStartDetails) onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final rect = sceneNodeRect(
      node: node,
      sceneSize: canvasSize,
      safeArea: EdgeInsets.zero,
      minHitTarget: minHitTarget,
    );
    final matrix = sceneNodeTransformMatrix(node.transform, rect.size);
    final points = {
      for (final handle in NodeResizeHandle.values)
        handle:
            rect.topLeft +
            MatrixUtils.transformPoint(
              matrix,
              handle.alignment.alongSize(rect.size),
            ),
    };
    final hitSize = 20 / viewportScale;
    final handleSize = 8 / viewportScale;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _SelectionPainter(points, 1.5 / viewportScale),
            ),
          ),
        ),
        if (showHandles && hasResizableProjection(node, rect.size))
          for (final entry in points.entries)
            Positioned(
              left: entry.value.dx - hitSize / 2,
              top: entry.value.dy - hitSize / 2,
              width: hitSize,
              height: hitSize,
              child: MouseRegion(
                cursor: entry.key.cursor,
                child: Listener(
                  onPointerCancel: (_) => onCancel(),
                  child: GestureDetector(
                    key: ValueKey('resize-${entry.key.name}'),
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: (details) => onStart(entry.key, details),
                    onPanUpdate: onUpdate,
                    onPanEnd: onStop,
                    onPanCancel: onCancel,
                    child: Center(
                      child: Container(
                        width: handleSize,
                        height: handleSize,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xff8b5cf6),
                            width: 1 / viewportScale,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter(this.points, this.strokeWidth);

  final Map<NodeResizeHandle, Offset> points;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addPolygon([
        points[NodeResizeHandle.topLeft]!,
        points[NodeResizeHandle.topRight]!,
        points[NodeResizeHandle.bottomRight]!,
        points[NodeResizeHandle.bottomLeft]!,
      ], true);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff8b5cf6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      strokeWidth != oldDelegate.strokeWidth ||
      points.entries.any(
        (entry) => oldDelegate.points[entry.key] != entry.value,
      );
}

class _GridPainter extends CustomPainter {
  const _GridPainter(this.spacing);

  final int spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x507f7f7f)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      spacing != oldDelegate.spacing;
}
