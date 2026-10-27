import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'node_geometry.dart';
import 'scene_editor.dart';
import 'studio_preferences.dart';
import 'studio_preview.dart';
import 'studio_preview_host.dart';
import 'studio_form.dart';
import 'node_arrangement_toolbar.dart';
import 'studio_timeline.dart';
import 'studio_state_graph.dart';

class StudioCanvas extends StatefulWidget {
  const StudioCanvas({
    required this.editor,
    required this.theme,
    required this.preferences,
    required this.dormant,
    required this.onToggleDormant,
    this.readOnly = false,
    super.key,
  });

  final bool readOnly;
  final SceneEditor? editor;
  final ThemeDefinition theme;
  final StudioPreferences preferences;
  final bool dormant;
  final VoidCallback onToggleDormant;

  @override
  State<StudioCanvas> createState() => _StudioCanvasState();
}

class _StudioCanvasState extends State<StudioCanvas> {
  StudioCanvasTool _tool = StudioCanvasTool.move;
  bool _lockAspectRatio = false;
  bool _snapToGuides = true;
  bool _handTool = false;
  bool _spacePan = false;
  bool _previewing = false;
  Duration? _elapsed;
  StudioTransition _transition = StudioTransition.wake;
  bool _showStateGraph = false;
  StudioPreviewScenario _scenario = StudioPreviewScenario.password;
  double? _zoom;
  int _resetView = 0;
  final _viewportKey = GlobalKey();
  final _focus = FocusNode(debugLabel: 'Studio canvas');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _selectTool(StudioCanvasTool tool) => setState(() {
    _tool = tool;
    _handTool = false;
  });

  void _fitView() => setState(() {
    _zoom = null;
    _resetView++;
  });

  double _getEffectiveZoom() {
    if (_zoom != null) return _zoom!;
    final viewport =
        _viewportKey.currentContext!.findRenderObject()! as RenderBox;
    final canvas = widget.editor!.document.canvas;
    return calculateFitZoom(
      viewportSize: viewport.size,
      referenceSize: Size(
        canvas.referenceWidth.toDouble(),
        canvas.referenceHeight.toDouble(),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode focus, KeyEvent event) {
    if (_previewing || _elapsed != null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      setState(() => _spacePan = event is! KeyUpEvent);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final session = widget.editor;
    if (session == null) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (widget.readOnly &&
        key != LogicalKeyboardKey.keyH &&
        !(key == LogicalKeyboardKey.digit1 && keyboard.isShiftPressed)) {
      return KeyEventResult.ignored;
    }
    if (keyboard.isControlPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        keyboard.isShiftPressed ? session.redo() : session.undo();
      } else if (key == LogicalKeyboardKey.keyY) {
        session.redo();
      } else if (key == LogicalKeyboardKey.keyD) {
        if (session.canDuplicateNode) session.duplicateSelectedNode();
      } else if (key == LogicalKeyboardKey.keyA) {
        session.selectNodes(
          session.document.nodes.map((node) => node.id).toSet(),
        );
      } else if (key == LogicalKeyboardKey.keyG) {
        keyboard.isShiftPressed
            ? session.ungroupSelection()
            : session.groupSelection();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    final step = keyboard.isShiftPressed ? 10.0 : 1.0;
    final delta = switch (key) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => null,
    };
    if (delta != null) {
      session.moveSelection(delta);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyV) {
      _selectTool(StudioCanvasTool.move);
    } else if (key == LogicalKeyboardKey.keyK) {
      _selectTool(StudioCanvasTool.scale);
    } else if (key == LogicalKeyboardKey.keyR) {
      _selectTool(
        keyboard.isShiftPressed
            ? StudioCanvasTool.rotate3d
            : StudioCanvasTool.rotate,
      );
    } else if (key == LogicalKeyboardKey.keyH) {
      setState(() => _handTool = true);
    } else if (key == LogicalKeyboardKey.digit1 && keyboard.isShiftPressed) {
      _fitView();
    } else if (key == LogicalKeyboardKey.delete) {
      if (session.canDeleteNode) session.deleteSelectedNode();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: _handleKeyEvent,
    onFocusChange: (focused) {
      if (!focused && _spacePan) setState(() => _spacePan = false);
    },
    child: ColoredBox(
      color: Theme.of(context).colorScheme.muted.withValues(alpha: 0.3),
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.editor]),
        builder: (context, _) {
          final session = widget.editor;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                key: const ValueKey('canvas-toolbar'),
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 150,
                      child: OutlineButton(
                        onPressed: _elapsed == null
                            ? widget.onToggleDormant
                            : null,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.dormant ? 'State: Dormant' : 'State: Login',
                          ).small(),
                        ),
                      ),
                    ),
                    Tooltip(
                      tooltip: (_) => const Text('Timeline'),
                      child: Button(
                        key: const ValueKey('canvas-timeline'),
                        style: _elapsed == null
                            ? const ButtonStyle.outlineIcon()
                            : const ButtonStyle.primaryIcon(),
                        onPressed: session == null
                            ? null
                            : () {
                                if (!session.applyDraft()) return;
                                setState(() {
                                  _elapsed = _elapsed == null
                                      ? Duration.zero
                                      : null;
                                  _previewing = false;
                                  _showStateGraph = false;
                                });
                              },
                        child: const Icon(LucideIcons.film, size: 16),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: StudioEnumSelect<StudioPreviewScenario>(
                        key: const ValueKey('preview-scenario'),
                        enabled: _elapsed == null,
                        value: _scenario,
                        values: StudioPreviewScenario.values,
                        formatValue: (scenario) => scenario.label,
                        onChanged: (scenario) {
                          if (widget.dormant) widget.onToggleDormant();
                          setState(() => _scenario = scenario);
                        },
                      ),
                    ),
                    Tooltip(
                      tooltip: (_) => const Text('State flow'),
                      child: Button(
                        key: const ValueKey('canvas-state-graph'),
                        style: _showStateGraph
                            ? const ButtonStyle.primaryIcon()
                            : const ButtonStyle.outlineIcon(),
                        onPressed: session == null
                            ? null
                            : () {
                                if (!session.applyDraft()) return;
                                setState(() {
                                  _showStateGraph = !_showStateGraph;
                                  _elapsed = null;
                                  _previewing = _showStateGraph;
                                });
                              },
                        child: const Icon(LucideIcons.gitBranch, size: 16),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      tooltip: (_) =>
                          Text(_previewing ? 'Edit canvas' : 'Preview'),
                      child: Button(
                        key: const ValueKey('canvas-preview'),
                        style: _previewing
                            ? const ButtonStyle.primaryIcon()
                            : const ButtonStyle.outlineIcon(),
                        onPressed: session == null
                            ? null
                            : () {
                                if (!_previewing && !session.applyDraft()) {
                                  return;
                                }
                                setState(() {
                                  _elapsed = null;
                                  _showStateGraph = false;
                                  _previewing = !_previewing;
                                });
                              },
                        child: Semantics(
                          label: _previewing ? 'Edit canvas' : 'Preview',
                          toggled: _previewing,
                          child: Icon(
                            _previewing
                                ? LucideIcons.mousePointer2
                                : LucideIcons.play,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    if (!widget.readOnly && !_previewing && _elapsed == null)
                      for (final tool in StudioCanvasTool.values)
                        Tooltip(
                          tooltip: (_) =>
                              Text('${tool.label} (${tool.shortcut})'),
                          child: Button(
                            key: ValueKey('tool-${tool.name}'),
                            style: !_handTool && tool == _tool
                                ? const ButtonStyle.primaryIcon()
                                : const ButtonStyle.outlineIcon(),
                            onPressed: () => _selectTool(tool),
                            child: Semantics(
                              label: tool.label,
                              child: Icon(switch (tool) {
                                StudioCanvasTool.move =>
                                  LucideIcons.mousePointer2,
                                StudioCanvasTool.scale => LucideIcons.scaling,
                                StudioCanvasTool.rotate => LucideIcons.rotateCw,
                                StudioCanvasTool.rotate3d =>
                                  LucideIcons.rotate3d,
                              }, size: 16),
                            ),
                          ),
                        ),
                    Tooltip(
                      tooltip: (_) =>
                          const Text('Hand (H) · Hold Space to pan'),
                      child: Button(
                        key: const ValueKey('canvas-hand'),
                        style: _handTool
                            ? const ButtonStyle.primaryIcon()
                            : const ButtonStyle.outlineIcon(),
                        onPressed: () => setState(() => _handTool = !_handTool),
                        child: Semantics(
                          label: 'Hand',
                          child: const Icon(LucideIcons.hand, size: 16),
                        ),
                      ),
                    ),
                    if (!widget.readOnly && !_previewing && _elapsed == null)
                      Tooltip(
                        tooltip: (_) =>
                            const Text('Smart guides · Alt to bypass'),
                        child: Button(
                          key: const ValueKey('smart-guides'),
                          style: _snapToGuides
                              ? const ButtonStyle.primaryIcon()
                              : const ButtonStyle.outlineIcon(),
                          onPressed: () =>
                              setState(() => _snapToGuides = !_snapToGuides),
                          child: const Icon(LucideIcons.magnet, size: 16),
                        ),
                      ),
                    if (!widget.readOnly && !_previewing && _elapsed == null)
                      Tooltip(
                        tooltip: (_) => const Text(
                          'Lock aspect ratio · Shift while resizing',
                        ),
                        child: Button(
                          key: const ValueKey('lock-aspect-ratio'),
                          style: _lockAspectRatio
                              ? const ButtonStyle.primaryIcon()
                              : const ButtonStyle.outlineIcon(),
                          onPressed: () => setState(
                            () => _lockAspectRatio = !_lockAspectRatio,
                          ),
                          child: Semantics(
                            label: 'Lock aspect ratio',
                            toggled: _lockAspectRatio,
                            child: Icon(
                              _lockAspectRatio
                                  ? LucideIcons.lock
                                  : LucideIcons.lockOpen,
                              size: 16,
                            ),
                          ),
                        ),
                      ),

                    OutlineButton(
                      key: const ValueKey('zoom-out'),
                      onPressed: session == null
                          ? null
                          : () => setState(
                              () => _zoom = clampStudioZoom(
                                _getEffectiveZoom() / 1.25,
                              ),
                            ),
                      child: const Icon(LucideIcons.minus, size: 16),
                    ),
                    OutlineButton(
                      key: const ValueKey('zoom-fit'),
                      onPressed: _fitView,
                      child: SizedBox(
                        width: 44,
                        child: Text(
                          _zoom == null ? 'Fit' : '${(_zoom! * 100).round()}%',
                          textAlign: TextAlign.center,
                        ).small(),
                      ),
                    ),
                    OutlineButton(
                      key: const ValueKey('zoom-in'),
                      onPressed: session == null
                          ? null
                          : () => setState(
                              () => _zoom = clampStudioZoom(
                                _getEffectiveZoom() * 1.25,
                              ),
                            ),
                      child: const Icon(LucideIcons.plus, size: 16),
                    ),
                    SizedBox(
                      width: 72,
                      child: OutlineButton(
                        key: const ValueKey('zoom-actual-size'),
                        onPressed: session == null
                            ? null
                            : () => setState(() => _zoom = 1),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: const Text('100%').small(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (session != null &&
                  !widget.readOnly &&
                  !_previewing &&
                  _elapsed == null &&
                  (session.selectedIds.length > 1 ||
                      session.selectedNode.layout != null))
                NodeArrangementToolbar(editor: session),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: session == null
                      ? const Center(child: Text('Unable to open scene'))
                      : Listener(
                          key: _viewportKey,
                          onPointerDown: _previewing
                              ? null
                              : (_) => _focus.requestFocus(),
                          child: StudioPreview(
                            key: ObjectKey(session),
                            theme: widget.theme,
                            readOnly:
                                widget.readOnly ||
                                _previewing ||
                                _elapsed != null,
                            interactive: _previewing || _elapsed != null,
                            document: session.previewDocument,
                            selectedId: session.selectedId,
                            selectedIds: session.selectedIds,
                            onSelectNodes: session.selectNodes,
                            onCommitNodes: session.updateNodes,
                            onPlaceNode: session.placeNode,
                            onUpdateText: session.updateNodeText,
                            snapToGuides: _snapToGuides,
                            dormant: widget.dormant,
                            scenario: _scenario,
                            playbackElapsed: _elapsed,
                            transition: _transition,
                            preferences: widget.preferences,
                            tool: _tool,
                            lockAspectRatio: _lockAspectRatio,
                            zoom: _zoom,
                            panEnabled: _handTool || _spacePan,
                            resetView: _resetView,
                            onZoom: (zoom) => setState(() => _zoom = zoom),
                            onSelect: (id) => session.selectNode(
                              id,
                              toggle: HardwareKeyboard.instance.isShiftPressed,
                            ),
                            onStartDrag: (id) {
                              if (!session.selectedIds.contains(id) &&
                                  !session.selectNode(
                                    id,
                                    toggle: HardwareKeyboard
                                        .instance
                                        .isShiftPressed,
                                  )) {
                                return null;
                              }
                              if (!session.applyDraft()) return null;
                              return session.document.nodes.firstWhere(
                                (node) => node.id == id,
                              );
                            },
                            onCommitDrag: session.updateNode,
                            onDragNodeChanged:
                                session.inspector.updatePreviewNode,
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(
                  children: [
                    if (session != null)
                      Text(
                        '${session.document.canvas.referenceWidth} × ${session.document.canvas.referenceHeight}',
                      ).small().muted(),
                    const Gap(16),
                    Expanded(
                      child: Text(
                        session == null
                            ? 'Choose a valid scene document.'
                            : _previewing
                            ? 'Preview focus, menus and motion · Choose scenarios for outcomes'
                            : widget.readOnly
                            ? 'Select a layer to inspect code'
                            : _handTool || _spacePan
                            ? 'Drag to pan'
                            : _tool.hint,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).small().muted(),
                    ),
                    const Gap(8),
                    Tooltip(
                      tooltip: (_) => const Text(
                        'Ctrl+wheel to zoom · Space+drag to pan · Shift+1 to fit',
                      ),
                      child: const Icon(LucideIcons.circleHelp, size: 14),
                    ),
                  ],
                ),
              ),
              if (_showStateGraph)
                StudioStateGraph(
                  dormant: widget.dormant,
                  scenario: _scenario,
                  onSelect: (dormant, scenario) {
                    if (dormant != widget.dormant) widget.onToggleDormant();
                    setState(() => _scenario = scenario);
                  },
                ),
              if (session != null && _elapsed != null)
                StudioTimeline(
                  duration: _getTimelineDuration(session),
                  elapsed: _elapsed!,
                  transition: _transition,
                  onTimeChanged: (elapsed) =>
                      setState(() => _elapsed = elapsed),
                  onTransitionChanged: (transition) => setState(() {
                    _transition = transition;
                    _elapsed = Duration.zero;
                  }),
                ),
            ],
          );
        },
      ),
    ),
  );

  Duration _getTimelineDuration(SceneEditor session) {
    var duration = const Duration(milliseconds: 1500);
    for (final node in session.document.nodes) {
      final timing = getSceneMotionDuration(
        node,
        widget.theme.tokens.mediumMotion,
      );
      if (timing > duration) duration = timing;
    }
    return duration;
  }
}
