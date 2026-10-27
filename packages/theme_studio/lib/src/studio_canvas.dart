import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'node_geometry.dart';
import 'scene_editor.dart';
import 'studio_preferences.dart';
import 'studio_input.dart';
import 'studio_components.dart';
import 'studio_preview.dart';
import 'studio_preview_host.dart';
import 'studio_form.dart';
import 'node_arrangement_toolbar.dart';
import 'studio_timeline.dart';
import 'studio_state_graph.dart';
import 'studio_workspace.dart';
import 'studio_workspace_layout.dart';
import 'studio_canvas_presets.dart';
import 'studio_comparison.dart';

class StudioCanvas extends StatefulWidget {
  const StudioCanvas({
    required this.editor,
    required this.theme,
    required this.preferences,
    required this.dormant,
    required this.onToggleDormant,
    this.readOnly = false,
    this.assetImageResolver,
    this.assetSvgLoader,
    this.assetFontLoader,
    super.key,
  });

  final bool readOnly;
  final SceneEditor? editor;
  final ThemeDefinition theme;
  final StudioPreferences preferences;
  final bool dormant;
  final VoidCallback onToggleDormant;
  final SceneImageProviderResolver? assetImageResolver;
  final SceneSvgLoader? assetSvgLoader;
  final SceneFontLoader? assetFontLoader;

  @override
  State<StudioCanvas> createState() => StudioCanvasState();
}

class StudioCanvasState extends State<StudioCanvas> {
  StudioCanvasTool _tool = StudioCanvasTool.move;
  bool _lockAspectRatio = false;
  bool _snapToGuides = true;
  bool _handTool = false;
  bool _spacePan = false;
  bool _previewing = false;
  Duration? _elapsed;
  StudioTransition _transition = StudioTransition.wake;
  bool _showStateGraph = false;
  Size? _responsiveSize;
  bool _comparing = false;
  bool _showRulers = false;
  StudioWorkspaceMode _workspaceMode = StudioWorkspaceMode.design;
  StudioPreviewScenario _scenario = StudioPreviewScenario.password;
  double? _zoom;
  int _resetView = 0;
  final _viewportKey = GlobalKey();
  final _focus = FocusNode(debugLabel: 'Studio canvas');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode =
        context
            .dependOnInheritedWidgetOfExactType<StudioWorkspaceScope>()
            ?.mode ??
        StudioWorkspaceMode.design;
    if (mode != _workspaceMode) {
      _workspaceMode = mode;
      _elapsed = mode == StudioWorkspaceMode.motion ? Duration.zero : null;
      _previewing = false;
      _comparing = false;
      _showStateGraph = false;
    }
  }

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

  void _toggleTimeline() {
    final session = widget.editor;
    if (session == null || !session.applyDraft()) return;
    setState(() {
      _elapsed = _elapsed == null ? Duration.zero : null;
      _previewing = false;
      _showStateGraph = false;
    });
  }

  void _toggleGraph() {
    final session = widget.editor;
    if (session == null || !session.applyDraft()) return;
    setState(() {
      _showStateGraph = !_showStateGraph;
      _elapsed = null;
      _previewing = _showStateGraph;
    });
  }

  void _togglePreview() {
    final session = widget.editor;
    if (session == null || (!_previewing && !session.applyDraft())) return;
    setState(() {
      _elapsed = null;
      _showStateGraph = false;
      _previewing = !_previewing;
    });
  }

  void _toggleComparison() {
    final session = widget.editor;
    if (session == null || !session.applyDraft()) return;
    setState(() {
      _comparing = !_comparing;
      _previewing = false;
      _elapsed = null;
      _showStateGraph = false;
    });
  }

  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (context
            .getInheritedWidgetOfExactType<StudioWorkspaceScope>()
            ?.presenting ??
        false) {
      return KeyEventResult.ignored;
    }
    final pan = widget.preferences.input.getBinding(StudioCommand.temporaryPan);
    if (event.logicalKey == pan?.key && (pan!.isPressed(event) || _spacePan)) {
      setState(() => _spacePan = event is! KeyUpEvent);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final command = widget.preferences.input.findCommand(event);
    final session = widget.editor;
    if (command == null || session == null) return KeyEventResult.ignored;
    switch (command) {
      case StudioCommand.fit:
        _fitView();
      case StudioCommand.actualSize:
        setState(() => _zoom = 1);
      case StudioCommand.zoomIn:
        setState(() => _zoom = clampStudioZoom(_getEffectiveZoom() * 1.25));
      case StudioCommand.zoomOut:
        setState(() => _zoom = clampStudioZoom(_getEffectiveZoom() / 1.25));
      case StudioCommand.hand:
        setState(() => _handTool = !_handTool);
      case StudioCommand.timeline:
        _toggleTimeline();
      case StudioCommand.stateGraph:
        _toggleGraph();
      case StudioCommand.compare:
        _toggleComparison();
      case StudioCommand.preview:
        _togglePreview();
      case StudioCommand.rulers:
        setState(() => _showRulers = !_showRulers);
      case StudioCommand.guides:
        setState(() => _snapToGuides = !_snapToGuides);
      default:
        if (widget.readOnly || _previewing || _elapsed != null || _comparing) {
          return KeyEventResult.ignored;
        }
        switch (command) {
          case StudioCommand.addText:
            session.createComponent(StudioComponent.text);
          case StudioCommand.addShape:
            session.createComponent(StudioComponent.rectangle);
          case StudioCommand.addFrame:
            session.createComponent(StudioComponent.frame);
          case StudioCommand.undo:
            session.undo();
          case StudioCommand.redo:
            session.redo();
          case StudioCommand.duplicate:
            if (session.canDuplicateNode) session.duplicateSelectedNode();
          case StudioCommand.delete:
            if (session.canDeleteNode) session.deleteSelectedNode();
          case StudioCommand.selectAll:
            session.selectNodes(
              session.document.nodes.map((node) => node.id).toSet(),
            );
          case StudioCommand.group:
            session.groupSelection();
          case StudioCommand.ungroup:
            session.ungroupSelection();
          case StudioCommand.move:
            _selectTool(StudioCanvasTool.move);
          case StudioCommand.scale:
            _selectTool(StudioCanvasTool.scale);
          case StudioCommand.rotate:
            _selectTool(StudioCanvasTool.rotate);
          case StudioCommand.rotate3d:
            _selectTool(StudioCanvasTool.rotate3d);
          case StudioCommand.nudgeLeft:
            session.moveSelection(const Offset(-1, 0));
          case StudioCommand.nudgeRight:
            session.moveSelection(const Offset(1, 0));
          case StudioCommand.nudgeUp:
            session.moveSelection(const Offset(0, -1));
          case StudioCommand.nudgeDown:
            session.moveSelection(const Offset(0, 1));
          case StudioCommand.fastLeft:
            session.moveSelection(const Offset(-10, 0));
          case StudioCommand.fastRight:
            session.moveSelection(const Offset(10, 0));
          case StudioCommand.fastUp:
            session.moveSelection(const Offset(0, -10));
          case StudioCommand.fastDown:
            session.moveSelection(const Offset(0, 10));
          default:
            return KeyEventResult.ignored;
        }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final presenting =
        context
            .dependOnInheritedWidgetOfExactType<StudioWorkspaceScope>()
            ?.presenting ??
        false;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) => handleKeyEvent(event),
      onFocusChange: (focused) {
        if (!focused && _spacePan) setState(() => _spacePan = false);
      },
      child: ColoredBox(
        color: Theme.of(context).colorScheme.muted.withValues(alpha: 0.3),
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.editor]),
          builder: (context, _) {
            final session = widget.editor;
            final toolControls = <Widget>[
              if (!widget.readOnly && !_previewing && _elapsed == null)
                for (final tool in StudioCanvasTool.values)
                  Tooltip(
                    tooltip: (_) => Text(
                      '${tool.label} · ${widget.preferences.input.getBinding(tool.command)?.getLabel() ?? 'Unbound'}',
                    ),
                    child: Button(
                      key: ValueKey('tool-${tool.name}'),
                      style: !_handTool && tool == _tool
                          ? const ButtonStyle.primaryIcon()
                          : const ButtonStyle.outlineIcon(),
                      onPressed: () => _selectTool(tool),
                      child: Semantics(
                        label: tool.label,
                        child: Icon(switch (tool) {
                          StudioCanvasTool.move => LucideIcons.mousePointer2,
                          StudioCanvasTool.scale => LucideIcons.scaling,
                          StudioCanvasTool.rotate => LucideIcons.rotateCw,
                          StudioCanvasTool.rotate3d => LucideIcons.rotate3d,
                        }, size: 16),
                      ),
                    ),
                  ),
              Tooltip(
                tooltip: (_) => Text(
                  'Hand · ${widget.preferences.input.getBinding(StudioCommand.hand)?.getLabel() ?? 'Unbound'} · Hold ${widget.preferences.input.getBinding(StudioCommand.temporaryPan)?.getLabel() ?? 'Unbound'} to pan',
                ),
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
                  tooltip: (_) => const Text('Smart guides · Alt to bypass'),
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
                  tooltip: (_) =>
                      const Text('Lock aspect ratio · Shift while resizing'),
                  child: Button(
                    key: const ValueKey('lock-aspect-ratio'),
                    style: _lockAspectRatio
                        ? const ButtonStyle.primaryIcon()
                        : const ButtonStyle.outlineIcon(),
                    onPressed: () =>
                        setState(() => _lockAspectRatio = !_lockAspectRatio),
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
            ];
            final zoomControls = <Widget>[
              OutlineButton(
                key: const ValueKey('zoom-out'),
                onPressed: session == null
                    ? null
                    : () => setState(
                        () =>
                            _zoom = clampStudioZoom(_getEffectiveZoom() / 1.25),
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
                        () =>
                            _zoom = clampStudioZoom(_getEffectiveZoom() * 1.25),
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
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!presenting && !_comparing)
                  Padding(
                    key: const ValueKey('canvas-toolbar'),
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 128,
                          child: OutlineButton(
                            onPressed: _elapsed == null
                                ? widget.onToggleDormant
                                : null,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                widget.dormant
                                    ? 'State: Dormant'
                                    : 'State: Login',
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
                            onPressed: session == null ? null : _toggleTimeline,
                            child: const Icon(LucideIcons.film, size: 16),
                          ),
                        ),
                        SizedBox(
                          width: 144,
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
                            onPressed: session == null ? null : _toggleGraph,
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
                            onPressed: session == null ? null : _togglePreview,
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
                      ],
                    ),
                  ),
                if (session != null &&
                    !presenting &&
                    !_comparing &&
                    !widget.readOnly &&
                    !_previewing &&
                    _elapsed == null &&
                    (session.selectedIds.length > 1 ||
                        session.selectedNode.layout != null))
                  NodeArrangementToolbar(editor: session),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!presenting && !_comparing)
                        Container(
                          key: const ValueKey('canvas-tool-rail'),
                          width: 44,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.background,
                            border: Border(
                              right: BorderSide(
                                color: Theme.of(context).colorScheme.border,
                              ),
                            ),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                const Gap(8),
                                for (final control in toolControls)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 3,
                                    ),
                                    child: control,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: Padding(
                          padding: presenting
                              ? EdgeInsets.zero
                              : const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                          child: session == null
                              ? const Center(
                                  child: Text('Unable to open scene'),
                                )
                              : Listener(
                                  key: _viewportKey,
                                  onPointerDown: _previewing || presenting
                                      ? null
                                      : (_) => _focus.requestFocus(),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Visibility(
                                        visible: !_comparing || presenting,
                                        maintainState: true,
                                        child: StudioPreview(
                                          key: ObjectKey(session),
                                          theme: widget.theme,
                                          readOnly:
                                              widget.readOnly ||
                                              _previewing ||
                                              _elapsed != null ||
                                              presenting,
                                          interactive:
                                              _previewing ||
                                              _elapsed != null ||
                                              presenting,
                                          document: session.previewDocument,
                                          selectedId: session.selectedId,
                                          selectedIds: session.selectedIds,
                                          onSelectNodes: session.selectNodes,
                                          onCommitNodes: session.updateNodes,
                                          onPlaceNode: session.placeNode,
                                          onCreateComponent:
                                              (component, position) =>
                                                  session.createComponent(
                                                    component,
                                                    position: position,
                                                  ),
                                          onUpdateText: session.updateNodeText,
                                          snapToGuides: _snapToGuides,
                                          showRulers: _showRulers,
                                          onPrepareGuide: session.applyDraft,
                                          onCreateGuide: session.createGuide,
                                          onUpdateGuide: session.updateGuide,
                                          onDeleteGuide: session.deleteGuide,
                                          assetImageResolver:
                                              widget.assetImageResolver,
                                          assetSvgLoader: widget.assetSvgLoader,
                                          assetFontLoader:
                                              widget.assetFontLoader,
                                          dormant: widget.dormant,
                                          scenario: _scenario,
                                          playbackElapsed: presenting
                                              ? null
                                              : _elapsed,
                                          transition: _transition,
                                          preferences: widget.preferences,
                                          tool: _tool,
                                          lockAspectRatio: _lockAspectRatio,
                                          zoom: presenting ? null : _zoom,
                                          viewportSize: presenting
                                              ? null
                                              : _responsiveSize,
                                          presenting: presenting,
                                          panEnabled:
                                              !presenting &&
                                              (_handTool || _spacePan),
                                          resetView: _resetView,
                                          onZoom: (zoom) =>
                                              setState(() => _zoom = zoom),
                                          onSelect: (id) => session.selectNode(
                                            id,
                                            toggle: HardwareKeyboard
                                                .instance
                                                .isShiftPressed,
                                          ),
                                          onStartDrag: (id) {
                                            if (!session.selectedIds.contains(
                                                  id,
                                                ) &&
                                                !session.selectNode(
                                                  id,
                                                  toggle: HardwareKeyboard
                                                      .instance
                                                      .isShiftPressed,
                                                )) {
                                              return null;
                                            }
                                            if (!session.applyDraft()) {
                                              return null;
                                            }
                                            return session.document.nodes
                                                .firstWhere(
                                                  (node) => node.id == id,
                                                );
                                          },
                                          onCommitDrag: session.updateNode,
                                          onDragNodeChanged: session
                                              .inspector
                                              .updatePreviewNode,
                                        ),
                                      ),
                                      if (_comparing && !presenting)
                                        StudioComparison(
                                          theme: widget.theme,
                                          document: session.previewDocument,
                                          preferences: widget.preferences,
                                          dormant: widget.dormant,
                                          scenario: _scenario,
                                          assetImageResolver:
                                              widget.assetImageResolver,
                                          assetSvgLoader: widget.assetSvgLoader,
                                          assetFontLoader:
                                              widget.assetFontLoader,
                                        ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!presenting)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (session != null)
                              SizedBox(
                                width: 170,
                                child: StudioSelect<StudioCanvasPreset>(
                                  key: const ValueKey('quick-resolution'),
                                  enabled: !widget.readOnly,
                                  value: StudioCanvasPreset.values
                                      .where(
                                        (preset) =>
                                            preset.width ==
                                                session
                                                    .document
                                                    .canvas
                                                    .referenceWidth &&
                                            preset.height ==
                                                session
                                                    .document
                                                    .canvas
                                                    .referenceHeight,
                                      )
                                      .firstOrNull,
                                  values: StudioCanvasPreset.values,
                                  placeholder: Text(
                                    '${session.document.canvas.referenceWidth} × ${session.document.canvas.referenceHeight}',
                                  ).small(),
                                  formatValue: (preset) =>
                                      '${preset.width} × ${preset.height}',
                                  onChanged: (preset) {
                                    if (!session.applyDraft()) return;
                                    session.updateScene(
                                      canvas: session.document.canvas.copyWith(
                                        referenceWidth: preset.width,
                                        referenceHeight: preset.height,
                                      ),
                                    );
                                    _fitView();
                                  },
                                ),
                              ),
                            OutlineButton(
                              key: const ValueKey('canvas-responsive'),
                              onPressed: session == null
                                  ? null
                                  : () => setState(() {
                                      _responsiveSize = _responsiveSize == null
                                          ? Size(
                                              session
                                                  .document
                                                  .canvas
                                                  .referenceWidth
                                                  .toDouble(),
                                              session
                                                  .document
                                                  .canvas
                                                  .referenceHeight
                                                  .toDouble(),
                                            )
                                          : null;
                                    }),
                              child: Text(
                                _responsiveSize == null
                                    ? 'Responsive'
                                    : 'Authored size',
                              ).small(),
                            ),
                            const Gap(8),
                            OutlineButton(
                              key: const ValueKey('canvas-compare'),
                              density: ButtonDensity.compact,
                              onPressed: session == null
                                  ? null
                                  : _toggleComparison,
                              child: Text(_comparing ? 'Single' : 'Compare')
                                  .small(),
                            ),
                            const Gap(8),
                            Tooltip(
                              tooltip: (_) => const Text(
                                'Rulers · Drag from a ruler to create a guide',
                              ),
                              child: Button(
                                key: const ValueKey('canvas-rulers'),
                                style: _showRulers
                                    ? const ButtonStyle.primaryIcon()
                                    : const ButtonStyle.outlineIcon(),
                                onPressed: () =>
                                    setState(() => _showRulers = !_showRulers),
                                child: const Icon(LucideIcons.ruler, size: 16),
                              ),
                            ),
                          ],
                        ),
                        Wrap(spacing: 4, runSpacing: 4, children: zoomControls),
                      ],
                    ),
                  ),
                if (_responsiveSize != null && !presenting)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        for (final horizontal in [true, false])
                          SizedBox(
                            width: 240,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    '${horizontal ? 'W' : 'H'} ${(horizontal ? _responsiveSize!.width : _responsiveSize!.height).round()} px',
                                  ).small(),
                                ),
                                Expanded(
                                  child: Slider(
                                    key: ValueKey(
                                      horizontal
                                          ? 'responsive-width'
                                          : 'responsive-height',
                                    ),
                                    min: 240,
                                    max: 3840,
                                    value: SliderValue.single(
                                      (horizontal
                                              ? _responsiveSize!.width
                                              : _responsiveSize!.height)
                                          .clamp(240, 3840),
                                    ),
                                    onChanged: (value) => setState(
                                      () => _responsiveSize = horizontal
                                          ? Size(
                                              value.value.roundToDouble(),
                                              _responsiveSize!.height,
                                            )
                                          : Size(
                                              _responsiveSize!.width,
                                              value.value.roundToDouble(),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (_showStateGraph && !presenting)
                  StudioStateGraph(
                    dormant: widget.dormant,
                    scenario: _scenario,
                    onSelect: (dormant, scenario) {
                      if (dormant != widget.dormant) widget.onToggleDormant();
                      setState(() => _scenario = scenario);
                    },
                  ),
                if (session != null && _elapsed != null && !presenting)
                  StudioTimeline(
                    editor: session,
                    fallbackDuration: widget.theme.bundle.tokens.mediumMotion,
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
  }

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
