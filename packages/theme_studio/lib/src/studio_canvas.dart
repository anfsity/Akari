import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'node_geometry.dart';
import 'scene_editor.dart';
import 'studio_preferences.dart';
import 'studio_preview.dart';

class StudioCanvas extends StatefulWidget {
  const StudioCanvas({
    required this.editor,
    required this.theme,
    required this.preferences,
    required this.dormant,
    required this.onToggleDormant,
    required this.onSave,
    super.key,
  });

  final SceneEditor? editor;
  final ThemeDefinition theme;
  final StudioPreferences preferences;
  final bool dormant;
  final VoidCallback onToggleDormant;
  final VoidCallback onSave;

  @override
  State<StudioCanvas> createState() => _StudioCanvasState();
}

class _StudioCanvasState extends State<StudioCanvas> {
  StudioCanvasTool _tool = StudioCanvasTool.move;
  bool _lockAspectRatio = false;
  bool _handTool = false;
  bool _spacePan = false;
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
    return math.min(
      viewport.size.width / canvas.referenceWidth,
      viewport.size.height / canvas.referenceHeight,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode focus, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      setState(() => _spacePan = event is! KeyUpEvent);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final session = widget.editor;
    if (session == null) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        keyboard.isShiftPressed ? session.redo() : session.undo();
      } else if (key == LogicalKeyboardKey.keyY) {
        session.redo();
      } else if (key == LogicalKeyboardKey.keyD) {
        session.duplicateSelectedNode();
      } else if (key == LogicalKeyboardKey.keyS) {
        widget.onSave();
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
      if (session.applyDraft()) {
        final node = session.selectedNode;
        session.updateNode(
          node.copyWith(
            rect: calculateMovedRect(
              rect: node.rect,
              canvasSize: Size(
                session.document.canvas.referenceWidth.toDouble(),
                session.document.canvas.referenceHeight.toDouble(),
              ),
              delta: delta,
            ),
          ),
        );
      }
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
              _PreviewHeader(
                dormant: widget.dormant,
                onToggleDormant: widget.onToggleDormant,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tool in StudioCanvasTool.values)
                      Tooltip(
                        tooltip: (_) =>
                            Text('${tool.label} (${tool.shortcut})'),
                        child: Button(
                          key: ValueKey('tool-${tool.name}'),
                          style: !_handTool && tool == _tool
                              ? const ButtonStyle.primary()
                              : const ButtonStyle.outline(),
                          onPressed: () => _selectTool(tool),
                          child: Semantics(
                            label: tool.label,
                            child: Icon(switch (tool) {
                              StudioCanvasTool.move =>
                                LucideIcons.mousePointer2,
                              StudioCanvasTool.scale => LucideIcons.scaling,
                              StudioCanvasTool.rotate => LucideIcons.rotateCw,
                              StudioCanvasTool.rotate3d => LucideIcons.rotate3d,
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
                            ? const ButtonStyle.primary()
                            : const ButtonStyle.outline(),
                        onPressed: () => setState(() => _handTool = !_handTool),
                        child: Semantics(
                          label: 'Hand',
                          child: const Icon(LucideIcons.hand, size: 16),
                        ),
                      ),
                    ),
                    Tooltip(
                      tooltip: (_) => const Text(
                        'Lock aspect ratio · Shift while resizing',
                      ),
                      child: Button(
                        key: const ValueKey('lock-aspect-ratio'),
                        style: _lockAspectRatio
                            ? const ButtonStyle.primary()
                            : const ButtonStyle.outline(),
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlineButton(
                          key: const ValueKey('zoom-out'),
                          onPressed: session == null
                              ? null
                              : () => setState(
                                  () => _zoom = (_getEffectiveZoom() / 1.25)
                                      .clamp(0.05, 8.0),
                                ),
                          child: const Icon(LucideIcons.minus, size: 16),
                        ),
                        const Gap(8),
                        OutlineButton(
                          key: const ValueKey('zoom-fit'),
                          onPressed: _fitView,
                          child: SizedBox(
                            width: 44,
                            child: Text(
                              _zoom == null
                                  ? 'Fit'
                                  : '${(_zoom! * 100).round()}%',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        const Gap(8),
                        OutlineButton(
                          key: const ValueKey('zoom-in'),
                          onPressed: session == null
                              ? null
                              : () => setState(
                                  () => _zoom = (_getEffectiveZoom() * 1.25)
                                      .clamp(0.05, 8.0),
                                ),
                          child: const Icon(LucideIcons.plus, size: 16),
                        ),
                        const Gap(8),
                        OutlineButton(
                          key: const ValueKey('zoom-actual-size'),
                          onPressed: session == null
                              ? null
                              : () => setState(() => _zoom = 1),
                          child: const Text('100%'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: session == null
                      ? const Center(child: Text('Unable to open scene'))
                      : Listener(
                          key: _viewportKey,
                          onPointerDown: (_) => _focus.requestFocus(),
                          child: StudioPreview(
                            key: ObjectKey(session),
                            theme: widget.theme,
                            document: session.document,
                            selectedId: session.selectedId,
                            dormant: widget.dormant,
                            preferences: widget.preferences,
                            tool: _tool,
                            lockAspectRatio: _lockAspectRatio,
                            zoom: _zoom,
                            panEnabled: _handTool || _spacePan,
                            resetView: _resetView,
                            onZoom: (zoom) => setState(() => _zoom = zoom),
                            onSelect: session.selectNode,
                            onStartDrag: (id) => session.selectNode(id)
                                ? session.selectedNode
                                : null,
                            onCommitDrag: session.updateNode,
                            onDragNodeChanged:
                                session.inspector.updatePreviewNode,
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: 40,
                  child: Center(
                    child: Text(
                      session == null
                          ? 'Choose a valid scene document.'
                          : '${session.document.canvas.referenceWidth} × ${session.document.canvas.referenceHeight}  ·  ${_handTool || _spacePan
                                ? 'Drag to pan'
                                : _tool == StudioCanvasTool.move
                                ? 'Drag to move · Handles resize · Shift locks ratio'
                                : _tool.hint}  ·  Ctrl+wheel zooms · Space pans',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ).small().muted(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.dormant, required this.onToggleDormant});

  final bool dormant;
  final VoidCallback onToggleDormant;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        const Text('Preview').semiBold(),
        const Spacer(),
        OutlineButton(
          onPressed: onToggleDormant,
          child: Text(dormant ? 'State: Dormant' : 'State: Login'),
        ),
      ],
    ),
  );
}
