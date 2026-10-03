import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'studio_preferences.dart';
import 'studio_preview_host.dart';

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
    required this.onMove,
    required this.preferences,
    super.key,
  });

  final ThemeDefinition theme;
  final SceneDocument document;
  final String selectedId;
  final bool dormant;
  final StudioPreferences preferences;
  final ValueChanged<String> onSelect;
  final SceneNode? Function(String id) onStartDrag;
  final ValueChanged<SceneNode> onMove;

  @override
  State<StudioPreview> createState() => _StudioPreviewState();
}

class _StudioPreviewState extends State<StudioPreview> {
  final _canvas = GlobalKey();
  ({SceneNode source, RenderBox canvas, Offset start})? _drag;
  SceneNode? _dragPreview;

  void _startDrag(String id, DragStartDetails details) {
    final node = widget.onStartDrag(id);
    if (node == null) return;
    final canvas = _canvas.currentContext?.findRenderObject();
    if (canvas is! RenderBox) return;
    setState(() {
      _drag = (
        source: node,
        canvas: canvas,
        start: canvas.globalToLocal(details.globalPosition),
      );
      _dragPreview = node;
    });
  }

  void _updateDrag(DragUpdateDetails details) {
    final drag = _drag;
    if (drag == null) return;
    final node = drag.source;
    // Convert through the canvas, not the transformed node: rotation, scale
    // and fit-to-workspace must not change the direction or speed of a drag.
    final canvas = drag.canvas;
    final delta = canvas.globalToLocal(details.globalPosition) - drag.start;
    final grid = widget.preferences.gridSize;
    var x = node.rect.x * canvas.size.width + delta.dx;
    var y = node.rect.y * canvas.size.height + delta.dy;
    if (widget.preferences.snapToGrid) {
      x = (x / grid).round() * grid.toDouble();
      y = (y / grid).round() * grid.toDouble();
    }
    setState(() {
      _dragPreview = node.copyWith(
        rect: node.rect.copyWith(
          x: (x / canvas.size.width).clamp(0.0, 1.0 - node.rect.width),
          y: (y / canvas.size.height).clamp(0.0, 1.0 - node.rect.height),
        ),
      );
    });
  }

  void _stopDrag({required bool commit}) {
    final node = _dragPreview;
    if (node == null) return;
    setState(() {
      _drag = null;
      _dragPreview = null;
    });
    if (commit) widget.onMove(node);
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
    final dragged = _dragPreview;
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
    return _PreviewViewport(
      canvasKey: _canvas,
      size: referenceSize,
      preferences: widget.preferences,
      child: _PreviewScene(
        theme: widget.theme,
        document: document,
        referenceSize: referenceSize,
        dormant: widget.dormant,
        nodeBuilder: _buildInteractiveNode,
      ),
    );
  }

  Widget _buildInteractiveNode(BuildContext context, SceneNode node) =>
      _PreviewNode(
        nodeId: node.id,
        selected: node.id == widget.selectedId,
        onSelect: () => widget.onSelect(node.id),
        onStartDrag: (details) => _startDrag(node.id, details),
        onUpdateDrag: _updateDrag,
        onStopDrag: (_) => _stopDrag(commit: true),
        onCancelDrag: () => _stopDrag(commit: false),
        child: _components.build(context, node),
      );
}

class _PreviewViewport extends StatelessWidget {
  const _PreviewViewport({
    required this.canvasKey,
    required this.size,
    required this.preferences,
    required this.child,
  });

  final Key canvasKey;
  final Size size;
  final StudioPreferences preferences;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: FittedBox(
      fit: BoxFit.contain,
      child: SizedBox.fromSize(
        key: canvasKey,
        size: size,
        child: CustomPaint(
          foregroundPainter: preferences.showGrid
              ? _GridPainter(preferences.gridSize)
              : null,
          child: child,
        ),
      ),
    ),
  );
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
          activePredicates: {
            ScenePredicate.isServiceReady,
            ScenePredicate.isAuthPrompting,
            ScenePredicate.hasSelectedUser,
            ScenePredicate.isSessionReady,
            if (dormant) ScenePredicate.isDormant,
          },
          nodeBuilder: nodeBuilder,
        ),
      ),
    ),
  );
}

class _PreviewNode extends StatelessWidget {
  const _PreviewNode({
    required this.nodeId,
    required this.selected,
    required this.onSelect,
    required this.onStartDrag,
    required this.onUpdateDrag,
    required this.onStopDrag,
    required this.onCancelDrag,
    required this.child,
  });

  final String nodeId;
  final bool selected;
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
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: selected
              ? Border.all(color: const Color(0xffa78bfa), width: 3)
              : null,
        ),
        child: ExcludeFocus(child: IgnorePointer(child: child)),
      ),
    ),
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
