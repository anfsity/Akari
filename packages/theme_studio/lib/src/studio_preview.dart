import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'node_geometry.dart';
import 'studio_preferences.dart';
import 'studio_preview_host.dart';
import 'studio_viewport.dart';
import 'smart_guides.dart';
import 'studio_timeline.dart';

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
    this.selectedIds,
    this.onSelectNodes,
    this.onCommitNodes,
    this.onPlaceNode,
    this.onUpdateText,
    this.snapToGuides = true,
    this.playbackElapsed,
    this.transition = StudioTransition.wake,
    this.presenting = false,
    this.readOnly = false,
    this.scenario = StudioPreviewScenario.password,
    this.interactive = false,
    this.lockAspectRatio = false,
    this.zoom,
    this.panEnabled = false,
    this.resetView = 0,
    this.onZoom,
    super.key,
  });

  final bool readOnly;
  final StudioPreviewScenario scenario;
  final bool interactive;
  final ThemeDefinition theme;
  final SceneDocument document;
  final String selectedId;
  final Set<String>? selectedIds;
  final ValueChanged<Set<String>>? onSelectNodes;
  final ValueChanged<List<SceneNode>>? onCommitNodes;
  final void Function(SceneNode, Offset)? onPlaceNode;
  final void Function(String, String)? onUpdateText;
  final bool snapToGuides;
  final Duration? playbackElapsed;
  final StudioTransition transition;
  final bool presenting;
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

class _StudioPreviewState extends State<StudioPreview>
    with SingleTickerProviderStateMixin {
  final _canvas = GlobalKey();
  _NodeDrag? _drag;
  final _otherDrags = <_NodeDrag>[];
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  Set<String> _marqueeSelection = {};
  List<double> _verticalGuides = [];
  List<double> _horizontalGuides = [];
  double _viewportScale = 1;
  SceneNode? _editingText;
  final _text = TextEditingController();
  final _textFocus = FocusNode(debugLabel: 'Canvas text');
  Set<String> get _selectedIds => widget.selectedIds ?? {widget.selectedId};

  Map<String, SceneNodeGeometry> _getGeometry(SceneDocument document) =>
      calculateSceneLayout(
        document: document,
        size: Size(
          document.canvas.referenceWidth.toDouble(),
          document.canvas.referenceHeight.toDouble(),
        ),
        minHitTarget: widget.theme.bundle.tokens.minHitTarget,
      );

  _NodeDrag _createDrag(
    SceneNode node,
    RenderBox canvas,
    Offset start,
    NodeResizeHandle? handle,
  ) {
    final geometry = _getGeometry(widget.document);
    final parent = node.parentId == null
        ? null
        : widget.document.nodes.firstWhere(
            (entry) => entry.id == node.parentId,
          );
    final padding = parent?.layout!.padding ?? 0;
    final parentSize = parent == null
        ? canvas.size
        : geometry[parent.id]!.rect.size;
    final parentMatrix =
        (parent == null
              ? Matrix4.identity()
              : geometry[parent.id]!.worldTransform.clone())
          ..translateByDouble(padding, padding, 0, 1);
    return _NodeDrag(
      source: node,
      canvas: canvas,
      start: start,
      tool: widget.tool,
      handle: handle,
      parentSize: Size(
        (parentSize.width - padding * 2).clamp(1, double.infinity),
        (parentSize.height - padding * 2).clamp(1, double.infinity),
      ),
      parentInverse: Matrix4.inverted(parentMatrix),
    );
  }

  void _startDrag(
    String id,
    DragStartDetails details, {
    NodeResizeHandle? handle,
  }) {
    // Before dragging begins on the canvas, any pending inspector draft must
    // be committed synchronously via onStartDrag so the drag starts from the
    // validated node state rather than uncommitted or stale document values.
    final node = widget.onStartDrag(id);
    if (node == null) return;
    final parent = node.parentId == null
        ? null
        : widget.document.nodes.firstWhere(
            (entry) => entry.id == node.parentId,
          );
    if (parent != null &&
        parent.layout!.direction != SceneLayoutDirection.absolute) {
      return;
    }
    final canvas = _canvas.currentContext?.findRenderObject();
    if (canvas is! RenderBox) return;
    setState(() {
      final start = canvas.globalToLocal(details.globalPosition);
      _drag = _createDrag(node, canvas, start, handle);
      _otherDrags.clear();
      if (handle == null && widget.tool == StudioCanvasTool.move) {
        final ids = {..._selectedIds, id};
        for (final other in widget.document.nodes) {
          if (other.id != id &&
              ids.contains(other.id) &&
              !ids.contains(other.parentId) &&
              other.parentId == node.parentId) {
            _otherDrags.add(_createDrag(other, canvas, start, null));
          }
        }
        final geometry = _getGeometry(widget.document);
        final drags = [_drag!, ..._otherDrags];
        final bounds = drags
            .map((drag) => geometry[drag.source.id]!.rect)
            .reduce((a, b) => a.expandToInclude(b));
        final padding = parent?.layout!.padding ?? 0;
        final size = _drag!.parentSize;
        final rect = SceneRect(
          x: (bounds.left - padding) / size.width,
          y: (bounds.top - padding) / size.height,
          width: bounds.width / size.width,
          height: bounds.height / size.height,
        );
        for (final drag in drags) {
          drag.movementBounds = rect;
        }
      }
    });
  }

  void _updateDrag(DragUpdateDetails details) {
    final drag = _drag;
    if (drag == null) return;
    var position = details.globalPosition;
    SceneNode calculate(_NodeDrag drag) => drag.calculateNode(
      position,
      lockAspectRatio:
          widget.lockAspectRatio || HardwareKeyboard.instance.isShiftPressed,
      minHitTarget: widget.theme.bundle.tokens.minHitTarget,
      gridSize: widget.preferences.snapToGrid
          ? widget.preferences.gridSize.toDouble()
          : null,
    );
    var updated = calculate(drag);
    _verticalGuides = [];
    _horizontalGuides = [];
    if (widget.snapToGuides &&
        !widget.preferences.snapToGrid &&
        !HardwareKeyboard.instance.isAltPressed &&
        drag.tool == StudioCanvasTool.move &&
        drag.handle == null) {
      final nodes = [
        updated,
        for (final other in _otherDrags) calculate(other),
      ];
      final ids = nodes.map((node) => node.id).toSet();
      for (final node in widget.document.layerOrder) {
        if (ids.contains(node.parentId)) ids.add(node.id);
      }
      final candidates = {for (final node in nodes) node.id: node};
      final geometry = _getGeometry(
        widget.document.copyWith(
          nodes: [
            for (final node in widget.document.nodes)
              candidates[node.id] ?? node,
          ],
        ),
      );
      final moving = nodes
          .map((node) => geometry[node.id]!.bounds)
          .reduce((a, b) => a.expandToInclude(b));
      final guides = calculateSmartGuides(
        moving: moving,
        targets: [
          for (final node in widget.document.nodes)
            if (!ids.contains(node.id) &&
                node.id != drag.source.parentId &&
                _isVisible(node))
              geometry[node.id]!.bounds,
        ],
        canvasSize: drag.canvas.size,
        tolerance: 6 / _viewportScale,
      );
      position = drag.canvas.localToGlobal(
        drag.canvas.globalToLocal(position) + guides.correction,
      );
      updated = calculate(drag);
      _verticalGuides = guides.vertical;
      _horizontalGuides = guides.horizontal;
    }
    final changed = drag.hasGeometryChange(updated);
    setState(() => drag.preview = updated);
    for (final other in _otherDrags) {
      other.preview = calculate(other);
    }
    if (changed) widget.onDragNodeChanged(updated);
  }

  void _stopDrag({required bool commit}) {
    final drag = _drag;
    if (drag == null) return;
    if (!commit) widget.onDragNodeChanged(drag.source);
    final nodes = [
      drag.preview,
      for (final other in _otherDrags) other.preview,
    ];
    setState(() {
      _drag = null;
      _otherDrags.clear();
      _verticalGuides = [];
      _horizontalGuides = [];
    });
    if (commit) {
      if (widget.onCommitNodes case final onCommit?) {
        onCommit(nodes);
      } else {
        widget.onCommitDrag(drag.preview);
      }
    }
  }

  late final _simulation = StudioPreviewHost(
    scenario: widget.playbackElapsed == null
        ? widget.scenario
        : widget.transition.toScenario,
  );
  StudioPreviewHost? _sourceSimulation;

  late GreeterThemeComponents _components;
  late final AnimationController _wake;

  @override
  void initState() {
    super.initState();
    _wake = AnimationController(
      vsync: this,
      duration: Duration.zero,
      value: widget.dormant ? 0 : 1,
    );
    _updateComponents();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateWake();
  }

  void _updateWake() {
    final disabled =
        !widget.interactive ||
        widget.theme.tokens.disableAnimations ||
        MediaQuery.disableAnimationsOf(context);
    _wake.duration = disabled
        ? Duration.zero
        : widget.theme.tokens.mediumMotion;
    if (disabled) {
      _wake.value = widget.dormant ? 0 : 1;
    } else if (widget.dormant) {
      _wake.reverse();
    } else {
      _wake.forward();
    }
  }

  @override
  void didUpdateWidget(StudioPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dormant != widget.dormant ||
        oldWidget.interactive != widget.interactive ||
        oldWidget.theme.tokens != widget.theme.tokens) {
      _updateWake();
    }
    if (oldWidget.scenario != widget.scenario ||
        oldWidget.transition != widget.transition ||
        (oldWidget.playbackElapsed == null) !=
            (widget.playbackElapsed == null)) {
      _simulation.updateScenario(
        widget.playbackElapsed == null
            ? widget.scenario
            : widget.transition.toScenario,
      );
      _sourceSimulation?.updateScenario(widget.transition.fromScenario);
      if (widget.playbackElapsed == null) {
        _sourceSimulation?.dispose();
        _sourceSimulation = null;
      }
    }
    if (!identical(oldWidget.theme, widget.theme) ||
        _hasCanvasChanged(oldWidget.document.canvas, widget.document.canvas)) {
      _updateComponents();
    }
  }

  static bool _hasCanvasChanged(SceneCanvas a, SceneCanvas b) =>
      a.referenceWidth != b.referenceWidth ||
      a.referenceHeight != b.referenceHeight ||
      a.fit != b.fit ||
      a.useSafeArea != b.useSafeArea;

  void _updateComponents() {
    _components = widget.theme.components(
      GreeterThemeContext(
        host: _simulation.host,
        tokens: widget.theme.tokens,
        canvas: widget.document.canvas,
      ),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    _textFocus.dispose();
    _wake.dispose();
    _simulation.dispose();
    _sourceSimulation?.dispose();
    super.dispose();
  }

  SceneDocument _getPreviewDocument() {
    if (_drag == null) return widget.document;
    final dragged = {
      _drag!.preview.id: _drag!.preview,
      for (final drag in _otherDrags) drag.preview.id: drag.preview,
    };
    return widget.document.copyWith(
      nodes: [
        for (final node in widget.document.nodes) dragged[node.id] ?? node,
      ],
    );
  }

  bool _isVisible(SceneNode node) {
    final predicates = _getPreviewPredicates(
      _simulation,
      widget.playbackElapsed == null
          ? widget.dormant
          : widget.transition.toDormant,
    );
    if (node.visibleWhen != null &&
        !evaluateSceneCondition(node.visibleWhen!, predicates)) {
      return false;
    }
    return node.parentId == null ||
        _isVisible(
          widget.document.nodes.firstWhere(
            (parent) => parent.id == node.parentId,
          ),
        );
  }

  void _startTextEditing(SceneNode node) {
    if (widget.readOnly || widget.interactive) return;
    final updated = widget.onStartDrag(node.id);
    if (updated == null) return;
    final definition =
        widget.theme.componentCatalog.components[node.componentId];
    final property = definition?.properties
        .whereType<ThemeTextProperty>()
        .where((property) => property.name == 'text')
        .firstOrNull;
    final value =
        property?.getValue(updated.properties) ?? updated.properties['text'];
    if (value == null) return;
    setState(() {
      _editingText = node;
      _text.text = value;
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: value.length,
      );
    });
    _textFocus.requestFocus();
  }

  void _commitText() {
    final node = _editingText;
    if (node == null) return;
    widget.onUpdateText?.call(node.id, _text.text);
    setState(() => _editingText = null);
  }

  @override
  Widget build(BuildContext context) {
    final document = _getPreviewDocument();
    final referenceSize = Size(
      document.canvas.referenceWidth.toDouble(),
      document.canvas.referenceHeight.toDouble(),
    );
    final geometry = _getGeometry(document);
    final predicates = _getPreviewPredicates(
      _simulation,
      widget.playbackElapsed == null
          ? widget.dormant
          : widget.transition.toDormant,
    );
    final elapsed = widget.playbackElapsed;
    final playback = elapsed == null
        ? null
        : ScenePlayback(
            elapsed: elapsed,
            from: _getPreviewPredicates(
              _sourceSimulation ??= StudioPreviewHost(
                scenario: widget.transition.fromScenario,
              ),
              widget.transition.fromDormant,
            ),
            enterAll: widget.transition == StudioTransition.entrance,
          );
    final duration = widget.theme.tokens.mediumMotion.inMicroseconds;
    final time = elapsed == null
        ? 0.0
        : duration == 0
        ? 1.0
        : (elapsed.inMicroseconds / duration).clamp(0.0, 1.0);
    final wake = elapsed == null
        ? _wake
        : AlwaysStoppedAnimation<double>(
            widget.transition.fromDormant == widget.transition.toDormant
                ? (widget.transition.toDormant ? 0 : 1)
                : widget.transition.toDormant
                ? 1 - time
                : time,
          );
    return StudioViewport(
      presenting: widget.presenting,
      canvasKey: _canvas,
      referenceSize: referenceSize,
      zoom: widget.zoom,
      resetView: widget.resetView,
      panEnabled: widget.panEnabled,
      onZoom: widget.onZoom ?? (_) {},
      childBuilder: (viewportScale) {
        _viewportScale = viewportScale;
        return DragTarget<SceneNode>(
          onWillAcceptWithDetails: (_) =>
              !widget.readOnly && !widget.interactive,
          onAcceptWithDetails: (details) {
            final canvas =
                _canvas.currentContext!.findRenderObject()! as RenderBox;
            final position = canvas.globalToLocal(details.offset);
            widget.onPlaceNode?.call(
              details.data,
              Offset(
                position.dx / referenceSize.width,
                position.dy / referenceSize.height,
              ),
            );
          },
          builder: (context, candidates, rejected) => CustomPaint(
            foregroundPainter: widget.preferences.showGrid
                ? _GridPainter(widget.preferences.gridSize)
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  key: const ValueKey('canvas-marquee'),
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onTap: widget.interactive
                      ? null
                      : () => widget.onSelectNodes?.call({}),
                  onPanStart: widget.readOnly || widget.interactive
                      ? null
                      : (details) => setState(() {
                          _marqueeStart = details.localPosition;
                          _marqueeEnd = details.localPosition;
                          _marqueeSelection =
                              HardwareKeyboard.instance.isShiftPressed
                              ? {..._selectedIds}
                              : {};
                        }),
                  onPanUpdate: widget.readOnly || widget.interactive
                      ? null
                      : (details) =>
                            setState(() => _marqueeEnd = details.localPosition),
                  onPanEnd: widget.readOnly || widget.interactive
                      ? null
                      : (_) {
                          final rect = Rect.fromPoints(
                            _marqueeStart!,
                            _marqueeEnd!,
                          );
                          final ids = {
                            ..._marqueeSelection,
                            for (final node in document.nodes)
                              if (_isVisible(node) &&
                                  rect.overlaps(geometry[node.id]!.bounds))
                                node.id,
                          };
                          setState(() {
                            _marqueeStart = null;
                            _marqueeEnd = null;
                          });
                          widget.onSelectNodes?.call(ids);
                        },
                  onPanCancel: widget.readOnly || widget.interactive
                      ? null
                      : () => setState(() {
                          _marqueeStart = null;
                          _marqueeEnd = null;
                        }),
                  child: _PreviewScene(
                    theme: widget.theme,
                    document: document,
                    referenceSize: referenceSize,
                    interactive: widget.interactive,
                    wakeProgress: wake,
                    playback: playback,
                    activePredicates: predicates,
                    nodeBuilder: _buildInteractiveNode,
                    frameBuilder: (context, node, child) =>
                        _buildInteractiveFrame(node, child),
                  ),
                ),
                for (final selected in document.nodes.where(
                  (node) => _selectedIds.contains(node.id),
                ))
                  if (_isVisible(selected) && !widget.interactive)
                    _NodeSelectionOverlay(
                      viewportScale: viewportScale,
                      geometry: geometry[selected.id]!,
                      showHandles:
                          !widget.readOnly &&
                          _selectedIds.length == 1 &&
                          widget.tool == StudioCanvasTool.move &&
                          (selected.parentId == null ||
                              document.nodes
                                      .firstWhere(
                                        (node) => node.id == selected.parentId,
                                      )
                                      .layout!
                                      .direction ==
                                  SceneLayoutDirection.absolute),
                      onStart: (handle, details) =>
                          _startDrag(selected.id, details, handle: handle),
                      onUpdate: _updateDrag,
                      onStop: (_) => _stopDrag(commit: true),
                      onCancel: () => _stopDrag(commit: false),
                    ),
                if (_marqueeStart != null)
                  Positioned.fromRect(
                    rect: Rect.fromPoints(_marqueeStart!, _marqueeEnd!),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x208b5cf6),
                          border: Border.all(color: const Color(0xff8b5cf6)),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: SmartGuidePainter(
                        vertical: _verticalGuides,
                        horizontal: _horizontalGuides,
                        scale: viewportScale,
                      ),
                    ),
                  ),
                ),
                if (_editingText case final node?)
                  Positioned.fromRect(
                    rect: geometry[node.id]!.bounds,
                    child: Localizations.override(
                      context: context,
                      delegates: const [DefaultMaterialLocalizations.delegate],
                      child: Material(
                        color: Colors.transparent,
                        child: Focus(
                          onKeyEvent: (_, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.escape) {
                              setState(() => _editingText = null);
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            key: const ValueKey('canvas-text-editor'),
                            controller: _text,
                            focusNode: _textFocus,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                            ),
                            onSubmitted: (_) => _commitText(),
                            onTapOutside: (_) => _commitText(),
                            decoration: const InputDecoration(
                              filled: true,
                              fillColor: Color(0xee18181b),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
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

  Widget _buildInteractiveNode(BuildContext context, SceneNode node) =>
      _PreviewNode(
        nodeId: node.id,
        interactive: widget.interactive,
        onSelect: () {
          if (!_selectedIds.contains(node.id) ||
              HardwareKeyboard.instance.isShiftPressed) {
            widget.onSelect(node.id);
          }
        },
        onDoubleTap: () => _startTextEditing(node),
        onStartDrag: widget.readOnly || widget.interactive
            ? null
            : (details) => _startDrag(node.id, details),
        onUpdateDrag: _updateDrag,
        onStopDrag: (_) => _stopDrag(commit: true),
        onCancelDrag: () => _stopDrag(commit: false),
        child: _components.build(context, node),
      );

  Widget _buildInteractiveFrame(SceneNode node, Widget child) =>
      widget.interactive
      ? child
      : GestureDetector(
          key: ValueKey('preview-${node.id}'),
          behavior: HitTestBehavior.translucent,
          onTap: () => widget.onSelect(node.id),
          onPanStart: widget.readOnly
              ? null
              : (details) => _startDrag(node.id, details),
          onPanUpdate: widget.readOnly ? null : _updateDrag,
          onPanEnd: widget.readOnly ? null : (_) => _stopDrag(commit: true),
          onPanCancel: () => _stopDrag(commit: false),
          child: child,
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
    required this.parentSize,
    required this.parentInverse,
  }) : preview = source;

  final SceneNode source;
  final RenderBox canvas;
  final Offset start;
  final Size parentSize;
  final Matrix4 parentInverse;
  final StudioCanvasTool tool;
  final NodeResizeHandle? handle;
  SceneNode preview;
  SceneRect? movementBounds;

  SceneNode calculateNode(
    Offset globalPosition, {
    required bool lockAspectRatio,
    required double minHitTarget,
    double? gridSize,
  }) {
    // Convert through the canvas so node transforms and viewport zoom do not
    // change the direction or speed of the pointer's movement.
    final delta =
        MatrixUtils.transformPoint(
          parentInverse,
          canvas.globalToLocal(globalPosition),
        ) -
        MatrixUtils.transformPoint(parentInverse, start);
    if (handle case final handle?) {
      return calculateResizedNode(
        source: source,
        canvasSize: parentSize,
        handle: handle,
        delta: delta,
        lockAspectRatio: lockAspectRatio,
        minHitTarget: minHitTarget,
        gridSize: gridSize,
      );
    }
    return switch (tool) {
      StudioCanvasTool.move => _calculateMovedNode(delta, gridSize),
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

  SceneNode _calculateMovedNode(Offset delta, double? gridSize) {
    final bounds = movementBounds ?? source.rect;
    final moved = calculateMovedRect(
      rect: bounds,
      canvasSize: parentSize,
      delta: delta,
      gridSize: gridSize,
    );
    return source.copyWith(
      rect: source.rect.copyWith(
        x: source.rect.x + moved.x - bounds.x,
        y: source.rect.y + moved.y - bounds.y,
      ),
    );
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
/// controls keep using shadcn; design mode keeps authoring hit tests stable.
class _PreviewScene extends StatelessWidget {
  const _PreviewScene({
    required this.theme,
    required this.document,
    required this.referenceSize,
    required this.interactive,
    required this.wakeProgress,
    required this.activePredicates,
    required this.nodeBuilder,
    required this.frameBuilder,
    required this.playback,
  });

  final ThemeDefinition theme;
  final SceneDocument document;
  final bool interactive;
  final Animation<double> wakeProgress;
  final Set<ScenePredicate> activePredicates;
  final SceneNodeBuilder nodeBuilder;
  final SceneFrameBuilder frameBuilder;
  final ScenePlayback? playback;
  final Size referenceSize;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme.materialTheme,
    home: MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: referenceSize,
        disableAnimations:
            !interactive || MediaQuery.disableAnimationsOf(context),
      ),
      child: Scaffold(
        body: SceneRuntime(
          document: document,
          theme: theme.bundle,
          backgroundBlurSigma: getBackgroundBlurAnimation(
            document.background,
            wakeProgress,
          ),
          activePredicates: activePredicates,
          nodeBuilder: nodeBuilder,
          frameBuilder: frameBuilder,
          playback: playback,
        ),
      ),
    ),
  );
}

class _PreviewNode extends StatelessWidget {
  const _PreviewNode({
    required this.nodeId,
    required this.interactive,
    required this.onSelect,
    required this.onDoubleTap,
    required this.onStartDrag,
    required this.onUpdateDrag,
    required this.onStopDrag,
    required this.onCancelDrag,
    required this.child,
  });

  final String nodeId;
  final bool interactive;
  final VoidCallback onSelect;
  final VoidCallback onDoubleTap;
  final GestureDragStartCallback? onStartDrag;
  final GestureDragUpdateCallback onUpdateDrag;
  final GestureDragEndCallback onStopDrag;
  final GestureDragCancelCallback onCancelDrag;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: interactive ? null : (_) => onSelect(),
    // Flutter reports an accepted pan's pointer cancellation as onPanEnd.
    // Clear the draft first so a cancelled pointer cannot commit a move.
    onPointerCancel: interactive ? null : (_) => onCancelDrag(),
    child: GestureDetector(
      key: ValueKey('preview-$nodeId'),
      behavior: HitTestBehavior.opaque,
      // Consume single taps immediately selected by the pointer listener so
      // double-click recognition cannot pass them to the blank-canvas tool.
      onTap: interactive ? null : () {},
      onDoubleTap: interactive ? null : onDoubleTap,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: onStartDrag,
      onPanUpdate: interactive ? null : onUpdateDrag,
      onPanEnd: interactive ? null : onStopDrag,
      onPanCancel: interactive ? null : onCancelDrag,
      child: ExcludeFocus(
        excluding: !interactive,
        child: IgnorePointer(ignoring: !interactive, child: child),
      ),
    ),
  );
}

Set<ScenePredicate> _getPreviewPredicates(
  StudioPreviewHost simulation,
  bool dormant,
) => getActiveScenePredicates(
  service: simulation.host.serviceSlots.value,
  auth: simulation.host.authPromptSlots.value,
  account: simulation.host.accountPickerSlots.value,
  session: simulation.host.sessionPickerSlots.value,
  power: simulation.host.powerSlots.value,
  dormant: dormant,
);

/// Selection belongs to the canvas, outside the component's paint transform.
/// Handles keep their screen size and remain usable on small or scaled nodes.
class _NodeSelectionOverlay extends StatelessWidget {
  const _NodeSelectionOverlay({
    required this.viewportScale,
    required this.geometry,
    required this.showHandles,
    required this.onStart,
    required this.onUpdate,
    required this.onStop,
    required this.onCancel,
  });

  final double viewportScale;
  final SceneNodeGeometry geometry;
  final bool showHandles;
  final void Function(NodeResizeHandle, DragStartDetails) onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final rect = Offset.zero & geometry.rect.size;
    final matrix = geometry.worldTransform;
    final points = calculateHandlePoints(rect: rect, matrix: matrix);
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
        if (showHandles && isInvertibleEditingPlane(matrix))
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
