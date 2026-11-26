import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../authoring/studio_components.dart';
import '../model/node_geometry.dart';
import '../model/studio_canvas_presets.dart';
import '../model/studio_input.dart';
import '../model/studio_preferences.dart';
import '../model/studio_scenario.dart';
import '../model/studio_theme.dart';
import '../model/studio_workspace_layout.dart';
import '../preview/studio_preview.dart';
import 'studio_canvas_controls.dart';
import 'studio_canvas_dock.dart';
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
  EdgeInsets _lastSafeArea = EdgeInsets.zero;
  final _viewportKey = GlobalKey();
  final _focus = FocusNode(debugLabel: 'Studio canvas');

  void _syncEditorSafeArea(EdgeInsets padding) {
    final session = widget.editor;
    if (session == null) return;
    final effective = session.document.canvas.useSafeArea
        ? padding
        : EdgeInsets.zero;
    if (effective == _lastSafeArea) return;
    _lastSafeArea = effective;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || session.isDisposed || session != widget.editor) return;
      session.updateAuthoring(
        componentCatalog: widget.theme.componentCatalog,
        presetCatalog: widget.theme.presetCatalog,
        layout: widget.theme.layout,
        minHitTarget: widget.theme.bundle.tokens.minHitTarget,
        safeArea: effective,
        fontFamilies: sceneFontFamilies.value,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncEditorSafeArea(MediaQuery.paddingOf(context));
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
  void didUpdateWidget(StudioCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != widget.editor) {
      _lastSafeArea = EdgeInsets.zero;
      _syncEditorSafeArea(MediaQuery.paddingOf(context));
      if (_elapsed != null) _elapsed = Duration.zero;
      if (_responsiveSize != null && widget.editor != null) {
        final canvas = widget.editor!.document.canvas;
        _responsiveSize = Size(
          canvas.referenceWidth.toDouble(),
          canvas.referenceHeight.toDouble(),
        );
      }
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
        if (!_canEditCanvas) {
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
              StudioCanvasTopBar(
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
                    : StudioCanvasDock(
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
                        onActualSize: () => setState(() => _zoom = 1),
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
                  ? StudioCanvasBottomDrawer(
                      session: session,
                      readOnly: widget.readOnly,
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
                  constraints.maxWidth < studioCompactDockWidth ? 136 : 88,
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
