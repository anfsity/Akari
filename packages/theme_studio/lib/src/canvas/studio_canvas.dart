import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'node_geometry.dart';
import '../authoring/scene_editor.dart';
import '../workspace/studio_preferences.dart';
import '../workspace/studio_input.dart';
import '../authoring/studio_components.dart';
import '../preview/studio_preview.dart';
import '../preview/studio_preview_host.dart';
import '../inspector/studio_form.dart';
import 'node_arrangement_toolbar.dart';
import '../timeline/studio_timeline.dart';
import '../timeline/studio_state_graph.dart';
import '../workspace/studio_workspace.dart';
import '../workspace/studio_workspace_layout.dart';
import 'studio_canvas_presets.dart';
import 'studio_comparison.dart';
import '../workspace/studio_theme.dart';
import '../workspace/studio_tooltip.dart';

const _compactDockWidth = 720.0;

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
    this.shaderLoader,
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
  final SceneShaderLoader? shaderLoader;

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
    final viewport = _viewportKey.currentContext?.findRenderObject();
    final canvas = widget.editor?.document.canvas;
    if (viewport is! RenderBox || !viewport.hasSize || canvas == null) {
      return 1;
    }
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
    if (session == null || !session.tryApplyDraft()) return;
    setState(() {
      _elapsed = _elapsed == null ? Duration.zero : null;
      _previewing = false;
      _showStateGraph = false;
    });
  }

  void _toggleGraph() {
    final session = widget.editor;
    if (session == null || !session.tryApplyDraft()) return;
    setState(() {
      _showStateGraph = !_showStateGraph;
      _elapsed = null;
      _previewing = _showStateGraph;
    });
  }

  void _togglePreview() {
    final session = widget.editor;
    if (session == null || (!_previewing && !session.tryApplyDraft())) return;
    setState(() {
      _elapsed = null;
      _showStateGraph = false;
      _previewing = !_previewing;
    });
  }

  void _toggleComparison() {
    final session = widget.editor;
    if (session == null || !session.tryApplyDraft()) return;
    setState(() {
      _comparing = !_comparing;
      _previewing = false;
      _elapsed = null;
      _showStateGraph = false;
    });
  }

  bool get _isEditingBlocked =>
      widget.readOnly || _previewing || _elapsed != null || _comparing;

  bool get _canEditCanvas => !_isEditingBlocked && _responsiveSize == null;

  bool _isPreviewReadOnly(bool presenting) =>
      widget.readOnly ||
      _responsiveSize != null ||
      _previewing ||
      _elapsed != null ||
      presenting;

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
        if (_isEditingBlocked) {
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

  void _selectScenario(StudioPreviewScenario scenario) {
    if (widget.dormant) widget.onToggleDormant();
    setState(() => _scenario = scenario);
  }

  void _toggleResponsive() {
    final session = widget.editor;
    if (session == null) return;
    setState(() {
      _responsiveSize = _responsiveSize == null
          ? Size(
              session.document.canvas.referenceWidth.toDouble(),
              session.document.canvas.referenceHeight.toDouble(),
            )
          : null;
    });
  }

  void _applyResolutionPreset(StudioCanvasPreset preset) {
    final session = widget.editor;
    if (session == null || !session.tryApplyDraft()) return;
    session.updateScene(
      canvas: session.document.canvas.copyWith(
        referenceWidth: preset.width,
        referenceHeight: preset.height,
      ),
    );
    _fitView();
  }

  @override
  Widget build(BuildContext context) {
    final presenting =
        context
            .dependOnInheritedWidgetOfExactType<StudioWorkspaceScope>()
            ?.presenting ??
        false;
    final colors = Theme.of(context).colorScheme;
    final session = widget.editor;
    final hasBottomDrawer =
        _responsiveSize != null ||
        (session != null && (_showStateGraph || _elapsed != null));
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) => handleKeyEvent(event),
      onFocusChange: (focused) {
        if (!focused && _spacePan) setState(() => _spacePan = false);
      },
      child: ColoredBox(
        color: getStudioStageColor(colors),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!presenting && !_comparing)
              _CanvasTopBar(
                session: session,
                readOnly: widget.readOnly,
                dormant: widget.dormant,
                scenario: _scenario,
                timelineOpen: _elapsed != null,
                showStateGraph: _showStateGraph,
                previewing: _previewing,
                onToggleDormant: widget.onToggleDormant,
                onSelectScenario: _selectScenario,
                onToggleTimeline: _toggleTimeline,
                onToggleGraph: _toggleGraph,
                onTogglePreview: _togglePreview,
              ),
            Expanded(
              child: _CanvasStage(
                presenting: presenting,
                viewportKey: _viewportKey,
                stageColor: colors.border,
                onPointerDown: _previewing || presenting
                    ? null
                    : () => _focus.requestFocus(),
                viewport: session == null
                    ? const Center(child: Text('Unable to open scene'))
                    : _CanvasViewportContent(
                        session: session,
                        theme: widget.theme,
                        preferences: widget.preferences,
                        readOnly: _isPreviewReadOnly(presenting),
                        interactive:
                            _previewing || _elapsed != null || presenting,
                        comparing: _comparing,
                        presenting: presenting,
                        dormant: widget.dormant,
                        scenario: _scenario,
                        elapsed: presenting ? null : _elapsed,
                        transition: _transition,
                        tool: _tool,
                        lockAspectRatio: _lockAspectRatio,
                        snapToGuides: _snapToGuides,
                        showRulers: _showRulers,
                        zoom: presenting ? null : _zoom,
                        responsiveSize: presenting ? null : _responsiveSize,
                        panEnabled: !presenting && (_handTool || _spacePan),
                        resetView: _resetView,
                        onZoom: (zoom) => setState(() => _zoom = zoom),
                        assetImageResolver: widget.assetImageResolver,
                        assetSvgLoader: widget.assetSvgLoader,
                        assetFontLoader: widget.assetFontLoader,
                        shaderLoader: widget.shaderLoader,
                      ),
                dock: presenting
                    ? null
                    : _CanvasDock(
                        session: session,
                        readOnly: widget.readOnly,
                        canEdit: _canEditCanvas && session != null,
                        tool: _tool,
                        handTool: _handTool,
                        snapToGuides: _snapToGuides,
                        lockAspectRatio: _lockAspectRatio,
                        showRulers: _showRulers,
                        comparing: _comparing,
                        responsiveActive: _responsiveSize != null,
                        zoom: _zoom,
                        input: widget.preferences.input,
                        onSelectTool: _selectTool,
                        onToggleHand: () =>
                            setState(() => _handTool = !_handTool),
                        onToggleGuides: () =>
                            setState(() => _snapToGuides = !_snapToGuides),
                        onToggleLockAspect: () => setState(
                          () => _lockAspectRatio = !_lockAspectRatio,
                        ),
                        onToggleRulers: () =>
                            setState(() => _showRulers = !_showRulers),
                        onSelectPreset: _applyResolutionPreset,
                        onToggleResponsive: _toggleResponsive,
                        onToggleComparison: _toggleComparison,
                        onZoomOut: () => setState(
                          () => _zoom = clampStudioZoom(
                            _getEffectiveZoom() / 1.25,
                          ),
                        ),
                        onFitView: _fitView,
                        onZoomIn: () => setState(
                          () => _zoom = clampStudioZoom(
                            _getEffectiveZoom() * 1.25,
                          ),
                        ),
                      ),
              ),
            ),
            AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: !presenting && hasBottomDrawer
                  ? _CanvasBottomDrawer(
                      session: session,
                      responsiveSize: _responsiveSize,
                      showStateGraph: _showStateGraph,
                      elapsed: _elapsed,
                      dormant: widget.dormant,
                      scenario: _scenario,
                      transition: _transition,
                      fallbackDuration: widget.theme.bundle.tokens.mediumMotion,
                      onResponsiveChanged: (size) =>
                          setState(() => _responsiveSize = size),
                      onSelectState: (dormant, scenario) {
                        if (dormant != widget.dormant) widget.onToggleDormant();
                        setState(() => _scenario = scenario);
                      },
                      onTimeChanged: (elapsed) =>
                          setState(() => _elapsed = elapsed),
                      onTransitionChanged: (transition) => setState(() {
                        _transition = transition;
                        _elapsed = Duration.zero;
                      }),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

Duration _getTimelineDuration(SceneEditor session, Duration fallbackDuration) {
  var duration = const Duration(milliseconds: 1500);
  for (final node in session.document.nodes) {
    final timing = getSceneMotionDuration(node, fallbackDuration);
    if (timing > duration) duration = timing;
    for (final rule in node.transitions) {
      final timing = getSceneMotionDuration(
        node.copyWith(
          tracks: const [],
          motionTiming: rule.timing.isDefault ? node.motionTiming : rule.timing,
        ),
        fallbackDuration,
      );
      if (timing > duration) duration = timing;
    }
  }
  return duration;
}

class _CanvasTopBar extends StatelessWidget {
  const _CanvasTopBar({
    required this.session,
    required this.readOnly,
    required this.dormant,
    required this.scenario,
    required this.timelineOpen,
    required this.showStateGraph,
    required this.previewing,
    required this.onToggleDormant,
    required this.onSelectScenario,
    required this.onToggleTimeline,
    required this.onToggleGraph,
    required this.onTogglePreview,
  });

  final SceneEditor? session;
  final bool readOnly;
  final bool dormant;
  final StudioPreviewScenario scenario;
  final bool timelineOpen;
  final bool showStateGraph;
  final bool previewing;
  final VoidCallback onToggleDormant;
  final ValueChanged<StudioPreviewScenario> onSelectScenario;
  final VoidCallback onToggleTimeline;
  final VoidCallback onToggleGraph;
  final VoidCallback onTogglePreview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasSession = session != null;
    return ColoredBox(
      color: colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            key: const ValueKey('canvas-toolbar'),
            constraints: const BoxConstraints(minHeight: 42),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 128,
                        child: GhostButton(
                          onPressed: timelineOpen ? null : onToggleDormant,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              dormant ? 'State: Dormant' : 'State: Login',
                            ).small(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 144,
                        child: StudioEnumSelect<StudioPreviewScenario>(
                          key: const ValueKey('preview-scenario'),
                          enabled: !timelineOpen,
                          value: scenario,
                          values: StudioPreviewScenario.values,
                          formatValue: (item) => item.label,
                          onChanged: onSelectScenario,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StudioTooltip(
                        tooltip: (_) => const Text('Timeline'),
                        child: Button(
                          key: const ValueKey('canvas-timeline'),
                          style: timelineOpen
                              ? const ButtonStyle.primaryIcon()
                              : const ButtonStyle.ghostIcon(),
                          onPressed: hasSession ? onToggleTimeline : null,
                          child: const Icon(LucideIcons.film, size: 16),
                        ),
                      ),
                      const Gap(4),
                      StudioTooltip(
                        tooltip: (_) => const Text('State flow'),
                        child: Button(
                          key: const ValueKey('canvas-state-graph'),
                          style: showStateGraph
                              ? const ButtonStyle.primaryIcon()
                              : const ButtonStyle.ghostIcon(),
                          onPressed: hasSession ? onToggleGraph : null,
                          child: const Icon(LucideIcons.gitBranch, size: 16),
                        ),
                      ),
                      const Gap(12),
                      const SizedBox(height: 20, child: VerticalDivider()),
                      const Gap(12),
                      StudioTooltip(
                        tooltip: (_) =>
                            Text(previewing ? 'Edit canvas' : 'Preview'),
                        child: Button(
                          key: const ValueKey('canvas-preview'),
                          style: previewing
                              ? const ButtonStyle.primaryIcon()
                              : const ButtonStyle.ghostIcon(),
                          onPressed: hasSession ? onTogglePreview : null,
                          child: Semantics(
                            label: previewing ? 'Edit canvas' : 'Preview',
                            toggled: previewing,
                            child: Icon(
                              previewing
                                  ? LucideIcons.mousePointer2
                                  : LucideIcons.play,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (session case final activeSession?
              when !readOnly && !previewing && !timelineOpen)
            ListenableBuilder(
              listenable: activeSession,
              builder: (context, _) {
                if (activeSession.selectedIds.isEmpty ||
                    (activeSession.selectedIds.length <= 1 &&
                        activeSession.selectedNode.layout == null)) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(),
                    NodeArrangementToolbar(editor: activeSession),
                  ],
                );
              },
            ),
          const Divider(),
        ],
      ),
    );
  }
}

class _CanvasStage extends StatelessWidget {
  const _CanvasStage({
    required this.presenting,
    required this.viewportKey,
    required this.stageColor,
    required this.onPointerDown,
    required this.viewport,
    required this.dock,
  });

  final bool presenting;
  final GlobalKey viewportKey;
  final Color stageColor;
  final VoidCallback? onPointerDown;
  final Widget viewport;
  final Widget? dock;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      fit: StackFit.expand,
      children: [
        if (!presenting)
          IgnorePointer(
            child: CustomPaint(painter: _StudioStageGrid(stageColor)),
          ),
        Padding(
          key: const ValueKey('canvas-viewport-area'),
          padding: presenting
              ? EdgeInsets.zero
              : EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  constraints.maxWidth < _compactDockWidth ? 136 : 88,
                ),
          child: Listener(
            key: viewportKey,
            onPointerDown: onPointerDown == null
                ? null
                : (_) => onPointerDown!(),
            child: viewport,
          ),
        ),
        if (dock case final floatingDock?)
          Positioned(left: 12, right: 12, bottom: 16, child: floatingDock),
      ],
    ),
  );
}

class _CanvasViewportContent extends StatelessWidget {
  const _CanvasViewportContent({
    required this.session,
    required this.theme,
    required this.preferences,
    required this.readOnly,
    required this.interactive,
    required this.comparing,
    required this.presenting,
    required this.dormant,
    required this.scenario,
    required this.elapsed,
    required this.transition,
    required this.tool,
    required this.lockAspectRatio,
    required this.snapToGuides,
    required this.showRulers,
    required this.zoom,
    required this.responsiveSize,
    required this.panEnabled,
    required this.resetView,
    required this.onZoom,
    required this.assetImageResolver,
    required this.assetSvgLoader,
    required this.assetFontLoader,
    required this.shaderLoader,
  });

  final SceneEditor session;
  final ThemeDefinition theme;
  final StudioPreferences preferences;
  final bool readOnly;
  final bool interactive;
  final bool comparing;
  final bool presenting;
  final bool dormant;
  final StudioPreviewScenario scenario;
  final Duration? elapsed;
  final StudioTransition transition;
  final StudioCanvasTool tool;
  final bool lockAspectRatio;
  final bool snapToGuides;
  final bool showRulers;
  final double? zoom;
  final Size? responsiveSize;
  final bool panEnabled;
  final int resetView;
  final ValueChanged<double> onZoom;
  final SceneImageProviderResolver? assetImageResolver;
  final SceneSvgLoader? assetSvgLoader;
  final SceneFontLoader? assetFontLoader;
  final SceneShaderLoader? shaderLoader;

  SceneNode? _startDrag(String id) {
    if (!session.selectedIds.contains(id) &&
        !session.selectNode(
          id,
          toggle: HardwareKeyboard.instance.isShiftPressed,
        )) {
      return null;
    }
    if (!session.tryApplyDraft()) return null;
    return session.document.nodes.firstWhere((node) => node.id == id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => Stack(
      fit: StackFit.expand,
      children: [
        Visibility(
          visible: !comparing || presenting,
          maintainState: true,
          child: StudioPreview(
            key: ObjectKey(session),
            theme: theme,
            readOnly: readOnly,
            interactive: interactive,
            document: session.previewDocument,
            selectedId: session.selectedId,
            selectedIds: session.selectedIds,
            onSelectNodes: session.selectNodes,
            onCommitNodes: session.updateNodes,
            onPlaceNode: session.placeNode,
            onCreateComponent: (component, position) =>
                session.createComponent(component, position: position),
            onUpdateText: session.updateNodeText,
            snapToGuides: snapToGuides,
            showRulers: showRulers,
            onPrepareGuide: session.tryApplyDraft,
            onCreateGuide: session.createGuide,
            onUpdateGuide: session.updateGuide,
            onDeleteGuide: session.deleteGuide,
            assetImageResolver: assetImageResolver,
            assetSvgLoader: assetSvgLoader,
            assetFontLoader: assetFontLoader,
            shaderLoader: shaderLoader,
            dormant: dormant,
            scenario: scenario,
            playbackElapsed: elapsed,
            transition: transition,
            preferences: preferences,
            tool: tool,
            lockAspectRatio: lockAspectRatio,
            zoom: zoom,
            viewportSize: responsiveSize,
            presenting: presenting,
            panEnabled: panEnabled,
            resetView: resetView,
            onZoom: onZoom,
            onSelect: (id) => session.selectNode(
              id,
              toggle: HardwareKeyboard.instance.isShiftPressed,
            ),
            onStartDrag: _startDrag,
            onDragNodeChanged: session.inspector.updatePreviewNode,
          ),
        ),
        if (comparing && !presenting)
          StudioComparison(
            theme: theme,
            document: session.previewDocument,
            preferences: preferences,
            dormant: dormant,
            scenario: scenario,
            assetImageResolver: assetImageResolver,
            assetSvgLoader: assetSvgLoader,
            assetFontLoader: assetFontLoader,
            shaderLoader: shaderLoader,
          ),
      ],
    ),
  );
}

class _CanvasDock extends StatelessWidget {
  const _CanvasDock({
    required this.session,
    required this.readOnly,
    required this.canEdit,
    required this.tool,
    required this.handTool,
    required this.snapToGuides,
    required this.lockAspectRatio,
    required this.showRulers,
    required this.comparing,
    required this.responsiveActive,
    required this.zoom,
    required this.input,
    required this.onSelectTool,
    required this.onToggleHand,
    required this.onToggleGuides,
    required this.onToggleLockAspect,
    required this.onToggleRulers,
    required this.onSelectPreset,
    required this.onToggleResponsive,
    required this.onToggleComparison,
    required this.onZoomOut,
    required this.onFitView,
    required this.onZoomIn,
  });

  final SceneEditor? session;
  final bool readOnly;
  final bool canEdit;
  final StudioCanvasTool tool;
  final bool handTool;
  final bool snapToGuides;
  final bool lockAspectRatio;
  final bool showRulers;
  final bool comparing;
  final bool responsiveActive;
  final double? zoom;
  final StudioInputBindings input;
  final ValueChanged<StudioCanvasTool> onSelectTool;
  final VoidCallback onToggleHand;
  final VoidCallback onToggleGuides;
  final VoidCallback onToggleLockAspect;
  final VoidCallback onToggleRulers;
  final ValueChanged<StudioCanvasPreset> onSelectPreset;
  final VoidCallback onToggleResponsive;
  final VoidCallback onToggleComparison;
  final VoidCallback onZoomOut;
  final VoidCallback onFitView;
  final VoidCallback onZoomIn;

  static IconData _getToolIcon(StudioCanvasTool tool) => switch (tool) {
    StudioCanvasTool.move => LucideIcons.mousePointer2,
    StudioCanvasTool.scale => LucideIcons.scaling,
    StudioCanvasTool.rotate => LucideIcons.rotateCw,
    StudioCanvasTool.rotate3d => LucideIcons.rotate3d,
  };

  void _openToolMenu(BuildContext context) {
    showDropdown<void>(
      context: context,
      alignment: Alignment.bottomLeft,
      anchorAlignment: Alignment.topLeft,
      offset: const Offset(0, -16),
      showDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      dismissDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 100),
      builder: (_) => DropdownMenu(
        children: [
          const MenuLabel(child: Text('Transform')),
          for (final item in StudioCanvasTool.values)
            MenuButton(
              key: ValueKey('tool-menu-${item.name}'),
              leading: Icon(_getToolIcon(item), size: 16),
              trailing: Text(
                input.getBinding(item.command)?.getLabel() ?? 'Unbound',
              ).xSmall().muted(),
              enabled: canEdit,
              onPressed: (_) => onSelectTool(item),
              child: Text(item.label),
            ),
          const MenuDivider(),
          MenuButton(
            key: const ValueKey('lock-aspect-ratio'),
            leading: Icon(
              lockAspectRatio ? LucideIcons.lock : LucideIcons.lockOpen,
              size: 16,
            ),
            trailing: lockAspectRatio
                ? const Icon(LucideIcons.check, size: 14)
                : null,
            enabled: canEdit,
            onPressed: (_) => onToggleLockAspect(),
            child: const Text('Lock aspect ratio'),
          ),
          MenuButton(
            key: const ValueKey('canvas-rulers'),
            leading: const Icon(LucideIcons.ruler, size: 16),
            trailing: showRulers
                ? const Icon(LucideIcons.check, size: 14)
                : null,
            onPressed: (_) => onToggleRulers(),
            child: const Text('Rulers & guides'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasSession = session != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactDockWidth;
        return Center(
          child: Container(
            key: const ValueKey('canvas-dock'),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.background,
              border: Border.all(color: colors.border.withValues(alpha: .7)),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DockButton(
                      id: 'tool-${tool.name}',
                      label:
                          '${tool.label} · ${input.getBinding(tool.command)?.getLabel() ?? 'Unbound'}',
                      icon: _getToolIcon(tool),
                      active: !handTool && canEdit,
                      onPressed: canEdit ? () => onSelectTool(tool) : null,
                    ),
                    _DockButton(
                      id: 'canvas-hand',
                      label:
                          'Hand · ${input.getBinding(StudioCommand.hand)?.getLabel() ?? 'Unbound'}',
                      icon: LucideIcons.hand,
                      active: handTool,
                      onPressed: hasSession ? onToggleHand : null,
                    ),
                    _DockButton(
                      id: 'smart-guides',
                      label: 'Smart guides · Alt to bypass',
                      icon: LucideIcons.magnet,
                      active: snapToGuides,
                      onPressed: canEdit ? onToggleGuides : null,
                    ),
                    Builder(
                      builder: (context) => _DockButton(
                        id: 'canvas-tool-menu',
                        label: 'Canvas tools',
                        icon: LucideIcons.ellipsis,
                        onPressed: hasSession
                            ? () => _openToolMenu(context)
                            : null,
                      ),
                    ),
                  ],
                ),
                if (!compact)
                  const SizedBox(height: 20, child: VerticalDivider()),
                if (session case final activeSession?)
                  ListenableBuilder(
                    listenable: activeSession,
                    builder: (context, _) {
                      final canvas = activeSession.document.canvas;
                      return SizedBox(
                        width: 132,
                        child: StudioSelect<StudioCanvasPreset>(
                          above: true,
                          theme: SelectTheme(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: (context, states, value) =>
                                ButtonVariance.ghost.decoration(
                                  context,
                                  states,
                                ),
                          ),
                          key: const ValueKey('quick-resolution'),
                          enabled: !readOnly,
                          value: StudioCanvasPreset.values
                              .where(
                                (preset) =>
                                    preset.width == canvas.referenceWidth &&
                                    preset.height == canvas.referenceHeight,
                              )
                              .firstOrNull,
                          values: StudioCanvasPreset.values,
                          placeholder: Text(
                            '${canvas.referenceWidth} × ${canvas.referenceHeight}',
                          ).small(),
                          formatValue: (preset) =>
                              '${preset.width} × ${preset.height}',
                          onChanged: onSelectPreset,
                        ),
                      );
                    },
                  ),
                StudioTooltip(
                  above: true,
                  enabled: compact,
                  tooltip: (_) => const Text('Responsive viewport'),
                  child: Semantics(
                    label: 'Responsive',
                    toggled: responsiveActive,
                    child: Toggle(
                      key: const ValueKey('canvas-responsive'),
                      value: responsiveActive,
                      onChanged: hasSession
                          ? (_) => onToggleResponsive()
                          : null,
                      style: const ButtonStyle.ghost(
                        density: ButtonDensity.dense,
                      ),
                      child: compact
                          ? const Icon(LucideIcons.monitor, size: 16)
                          : const Text('Responsive').small(),
                    ),
                  ),
                ),
                if (!compact)
                  const SizedBox(height: 20, child: VerticalDivider()),
                DecoratedBox(
                  key: const ValueKey('canvas-compare'),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 2,
                      children: [
                        for (final (isCompare, icon) in [
                          (false, LucideIcons.square),
                          (true, LucideIcons.layoutGrid),
                        ])
                          StudioTooltip(
                            above: true,
                            tooltip: (_) => Text(
                              isCompare ? 'Compare view' : 'Single view',
                            ),
                            child: Semantics(
                              label: isCompare ? 'Compare' : 'Single',
                              selected: comparing == isCompare,
                              child: Button(
                                key: ValueKey(
                                  isCompare
                                      ? 'canvas-view-compare'
                                      : 'canvas-view-single',
                                ),
                                style: comparing == isCompare
                                    ? const ButtonStyle.secondary(
                                        density: ButtonDensity.iconDense,
                                      )
                                    : const ButtonStyle.ghost(
                                        density: ButtonDensity.iconDense,
                                      ),
                                onPressed: hasSession
                                    ? () {
                                        if (comparing != isCompare) {
                                          onToggleComparison();
                                        }
                                      }
                                    : null,
                                child: Icon(icon, size: 15),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!compact)
                  const SizedBox(height: 20, child: VerticalDivider()),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DockButton(
                      id: 'zoom-out',
                      label: 'Zoom out',
                      icon: LucideIcons.minus,
                      onPressed: hasSession ? onZoomOut : null,
                    ),
                    _DockButton(
                      id: 'zoom-fit',
                      label: 'Fit canvas',
                      text: zoom == null ? 'Fit' : '${(zoom! * 100).round()}%',
                      onPressed: hasSession ? onFitView : null,
                    ),
                    _DockButton(
                      id: 'zoom-in',
                      label: 'Zoom in',
                      icon: LucideIcons.plus,
                      onPressed: hasSession ? onZoomIn : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.id,
    required this.label,
    required this.onPressed,
    this.icon,
    this.text,
    this.active,
  });

  final String id;
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? text;
  final bool? active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isActive = active ?? false;
    return StudioTooltip(
      above: true,
      tooltip: (_) => Text(label),
      child: Semantics(
        label: icon == null ? null : label,
        toggled: active,
        child: Button(
          key: ValueKey(id),
          style:
              ButtonStyle.ghost(
                density: icon == null
                    ? ButtonDensity.dense
                    : ButtonDensity.icon,
                shape: icon == null
                    ? ButtonShape.rectangle
                    : ButtonShape.circle,
              ).copyWith(
                decoration: (context, states, value) {
                  final decoration = value as BoxDecoration;
                  return decoration.copyWith(
                    color: isActive
                        ? colors.primary.withValues(alpha: .08)
                        : decoration.color,
                  );
                },
              ),
          onPressed: onPressed,
          child: icon == null
              ? Text(text ?? label).small()
              : Icon(icon, size: 16, color: isActive ? colors.primary : null),
        ),
      ),
    );
  }
}

class _CanvasBottomDrawer extends StatelessWidget {
  const _CanvasBottomDrawer({
    required this.session,
    required this.responsiveSize,
    required this.showStateGraph,
    required this.elapsed,
    required this.dormant,
    required this.scenario,
    required this.transition,
    required this.fallbackDuration,
    required this.onResponsiveChanged,
    required this.onSelectState,
    required this.onTimeChanged,
    required this.onTransitionChanged,
  });

  final SceneEditor? session;
  final Size? responsiveSize;
  final bool showStateGraph;
  final Duration? elapsed;
  final bool dormant;
  final StudioPreviewScenario scenario;
  final StudioTransition transition;
  final Duration fallbackDuration;
  final ValueChanged<Size> onResponsiveChanged;
  final void Function(bool, StudioPreviewScenario) onSelectState;
  final ValueChanged<Duration> onTimeChanged;
  final ValueChanged<StudioTransition> onTransitionChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (responsiveSize case final size?) ...[
            const Divider(),
            _ResponsiveViewportBar(size: size, onChanged: onResponsiveChanged),
          ],
          if (session case final activeSession?
              when showStateGraph || elapsed != null)
            ListenableBuilder(
              listenable: activeSession,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showStateGraph) ...[
                    const Divider(),
                    StudioStateGraph(
                      editor: activeSession,
                      dormant: dormant,
                      scenario: scenario,
                      onSelect: onSelectState,
                    ),
                  ],
                  if (elapsed case final activeElapsed?) ...[
                    const Divider(),
                    StudioTimeline(
                      editor: activeSession,
                      fallbackDuration: fallbackDuration,
                      duration: _getTimelineDuration(
                        activeSession,
                        fallbackDuration,
                      ),
                      elapsed: activeElapsed,
                      transition: transition,
                      onTimeChanged: onTimeChanged,
                      onTransitionChanged: onTransitionChanged,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ResponsiveViewportBar extends StatelessWidget {
  const _ResponsiveViewportBar({required this.size, required this.onChanged});

  final Size size;
  final ValueChanged<Size> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    '${horizontal ? 'W' : 'H'} ${(horizontal ? size.width : size.height).round()} px',
                  ).small(),
                ),
                Expanded(
                  child: Slider(
                    key: ValueKey(
                      horizontal ? 'responsive-width' : 'responsive-height',
                    ),
                    min: 240,
                    max: 3840,
                    value: SliderValue.single(
                      (horizontal ? size.width : size.height).clamp(240, 3840),
                    ),
                    onChanged: (value) => onChanged(
                      horizontal
                          ? Size(value.value.roundToDouble(), size.height)
                          : Size(size.width, value.value.roundToDouble()),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _StudioStageGrid extends CustomPainter {
  const _StudioStageGrid(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 12.0; x < size.width; x += 24) {
      for (var y = 12.0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StudioStageGrid oldDelegate) =>
      oldDelegate.color != color;
}
