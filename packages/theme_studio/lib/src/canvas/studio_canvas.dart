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

  IconData _getToolIcon(StudioCanvasTool tool) => switch (tool) {
    StudioCanvasTool.move => LucideIcons.mousePointer2,
    StudioCanvasTool.scale => LucideIcons.scaling,
    StudioCanvasTool.rotate => LucideIcons.rotateCw,
    StudioCanvasTool.rotate3d => LucideIcons.rotate3d,
  };

  Widget _buildDockButton({
    required String key,
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    String? text,
    bool active = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      tooltip: (_) => Text(label),
      child: Semantics(
        label: label,
        toggled: active,
        child: Button(
          key: ValueKey(key),
          style:
              ButtonStyle.ghost(
                density: icon == null
                    ? ButtonDensity.dense
                    : ButtonDensity.icon,
                shape: icon == null
                    ? ButtonShape.rectangle
                    : ButtonShape.circle,
              ).copyWith(
                decoration: (context, states, value) =>
                    (value as BoxDecoration).copyWith(
                      color: active
                          ? colors.primary.withValues(alpha: .08)
                          : null,
                    ),
              ),
          onPressed: onPressed,
          child: icon == null
              ? Text(text ?? label).small()
              : Icon(icon, size: 16, color: active ? colors.primary : null),
        ),
      ),
    );
  }

  void _openToolMenu(BuildContext context, {required bool canEdit}) {
    showDropdown<void>(
      context: context,
      alignment: Alignment.bottomLeft,
      anchorAlignment: Alignment.topLeft,
      builder: (_) => DropdownMenu(
        children: [
          const MenuLabel(child: Text('Transform')),
          for (final tool in StudioCanvasTool.values)
            MenuButton(
              key: ValueKey('tool-menu-${tool.name}'),
              leading: Icon(_getToolIcon(tool), size: 16),
              trailing: Text(
                widget.preferences.input.getBinding(tool.command)?.getLabel() ??
                    'Unbound',
              ).xSmall().muted(),
              enabled: canEdit,
              onPressed: (_) => _selectTool(tool),
              child: Text(tool.label),
            ),
          const MenuDivider(),
          MenuButton(
            key: const ValueKey('lock-aspect-ratio'),
            leading: Icon(
              _lockAspectRatio ? LucideIcons.lock : LucideIcons.lockOpen,
              size: 16,
            ),
            trailing: _lockAspectRatio
                ? const Icon(LucideIcons.check, size: 14)
                : null,
            enabled: canEdit,
            onPressed: (_) =>
                setState(() => _lockAspectRatio = !_lockAspectRatio),
            child: const Text('Lock aspect ratio'),
          ),
          MenuButton(
            key: const ValueKey('canvas-rulers'),
            leading: const Icon(LucideIcons.ruler, size: 16),
            trailing: _showRulers
                ? const Icon(LucideIcons.check, size: 14)
                : null,
            onPressed: (_) => setState(() => _showRulers = !_showRulers),
            child: const Text('Rulers & guides'),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasDock(SceneEditor? session) {
    final colors = Theme.of(context).colorScheme;
    final canEdit =
        session != null &&
        !widget.readOnly &&
        !_previewing &&
        _elapsed == null &&
        !_comparing &&
        _responsiveSize == null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final responsiveLabel = _responsiveSize == null
            ? 'Responsive'
            : 'Authored size';
        final comparisonLabel = _comparing ? 'Single' : 'Compare';
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
                    _buildDockButton(
                      key: 'tool-${_tool.name}',
                      label:
                          '${_tool.label} · ${widget.preferences.input.getBinding(_tool.command)?.getLabel() ?? 'Unbound'}',
                      icon: _getToolIcon(_tool),
                      active: !_handTool && canEdit,
                      onPressed: canEdit ? () => _selectTool(_tool) : null,
                    ),
                    _buildDockButton(
                      key: 'canvas-hand',
                      label:
                          'Hand · ${widget.preferences.input.getBinding(StudioCommand.hand)?.getLabel() ?? 'Unbound'}',
                      icon: LucideIcons.hand,
                      active: _handTool,
                      onPressed: session == null
                          ? null
                          : () => setState(() => _handTool = !_handTool),
                    ),
                    _buildDockButton(
                      key: 'smart-guides',
                      label: 'Smart guides · Alt to bypass',
                      icon: LucideIcons.magnet,
                      active: _snapToGuides,
                      onPressed: canEdit
                          ? () => setState(() => _snapToGuides = !_snapToGuides)
                          : null,
                    ),
                    Builder(
                      builder: (context) => _buildDockButton(
                        key: 'canvas-tool-menu',
                        label: 'Canvas tools',
                        icon: LucideIcons.ellipsis,
                        onPressed: session == null
                            ? null
                            : () => _openToolMenu(context, canEdit: canEdit),
                      ),
                    ),
                  ],
                ),
                if (!compact)
                  const SizedBox(height: 20, child: VerticalDivider()),
                if (session != null)
                  SizedBox(
                    width: compact ? 128 : 148,
                    child: StudioSelect<StudioCanvasPreset>(
                      theme: SelectTheme(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: (context, states, value) =>
                            (value as BoxDecoration).copyWith(
                              border: const Border(),
                              color: Colors.transparent,
                            ),
                      ),
                      key: const ValueKey('quick-resolution'),
                      enabled: !widget.readOnly,
                      value: StudioCanvasPreset.values
                          .where(
                            (preset) =>
                                preset.width ==
                                    session.document.canvas.referenceWidth &&
                                preset.height ==
                                    session.document.canvas.referenceHeight,
                          )
                          .firstOrNull,
                      values: StudioCanvasPreset.values,
                      placeholder: Text(
                        '${session.document.canvas.referenceWidth} × ${session.document.canvas.referenceHeight}',
                      ).small(),
                      formatValue: (preset) =>
                          '${preset.width} × ${preset.height}',
                      onChanged: (preset) {
                        if (!session.tryApplyDraft()) return;
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDockButton(
                      key: 'canvas-responsive',
                      label: responsiveLabel,
                      icon: compact ? LucideIcons.monitor : null,
                      active: _responsiveSize != null,
                      onPressed: session == null
                          ? null
                          : () => setState(() {
                              _responsiveSize = _responsiveSize == null
                                  ? Size(
                                      session.document.canvas.referenceWidth
                                          .toDouble(),
                                      session.document.canvas.referenceHeight
                                          .toDouble(),
                                    )
                                  : null;
                            }),
                    ),
                    _buildDockButton(
                      key: 'canvas-compare',
                      label: comparisonLabel,
                      icon: compact ? LucideIcons.columns2 : null,
                      active: _comparing,
                      onPressed: session == null ? null : _toggleComparison,
                    ),
                  ],
                ),
                if (!compact)
                  const SizedBox(height: 20, child: VerticalDivider()),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDockButton(
                      key: 'zoom-out',
                      label: 'Zoom out',
                      icon: LucideIcons.minus,
                      onPressed: session == null
                          ? null
                          : () => setState(
                              () => _zoom = clampStudioZoom(
                                _getEffectiveZoom() / 1.25,
                              ),
                            ),
                    ),
                    _buildDockButton(
                      key: 'zoom-fit',
                      label: 'Fit canvas',
                      text: _zoom == null
                          ? 'Fit'
                          : '${(_zoom! * 100).round()}%',
                      onPressed: session == null ? null : _fitView,
                    ),
                    _buildDockButton(
                      key: 'zoom-in',
                      label: 'Zoom in',
                      icon: LucideIcons.plus,
                      onPressed: session == null
                          ? null
                          : () => setState(
                              () => _zoom = clampStudioZoom(
                                _getEffectiveZoom() * 1.25,
                              ),
                            ),
                    ),
                    _buildDockButton(
                      key: 'zoom-actual-size',
                      label: 'Actual size · 100%',
                      text: '100%',
                      onPressed: session == null
                          ? null
                          : () => setState(() => _zoom = 1),
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

  @override
  Widget build(BuildContext context) {
    final presenting =
        context
            .dependOnInheritedWidgetOfExactType<StudioWorkspaceScope>()
            ?.presenting ??
        false;
    final colors = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) => handleKeyEvent(event),
      onFocusChange: (focused) {
        if (!focused && _spacePan) setState(() => _spacePan = false);
      },
      child: ColoredBox(
        color: getStudioStageColor(colors),
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.editor]),
          builder: (context, _) {
            final session = widget.editor;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!presenting && !_comparing)
                  ColoredBox(
                    color: colors.background,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstrainedBox(
                          key: const ValueKey('canvas-toolbar'),
                          constraints: const BoxConstraints(minHeight: 42),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
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
                                    SizedBox(
                                      width: 144,
                                      child:
                                          StudioEnumSelect<
                                            StudioPreviewScenario
                                          >(
                                            key: const ValueKey(
                                              'preview-scenario',
                                            ),
                                            enabled: _elapsed == null,
                                            value: _scenario,
                                            values:
                                                StudioPreviewScenario.values,
                                            formatValue: (scenario) =>
                                                scenario.label,
                                            onChanged: (scenario) {
                                              if (widget.dormant) {
                                                widget.onToggleDormant();
                                              }
                                              setState(
                                                () => _scenario = scenario,
                                              );
                                            },
                                          ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Tooltip(
                                      tooltip: (_) => const Text('Timeline'),
                                      child: Button(
                                        key: const ValueKey('canvas-timeline'),
                                        style: _elapsed == null
                                            ? const ButtonStyle.ghostIcon()
                                            : const ButtonStyle.primaryIcon(),
                                        onPressed: session == null
                                            ? null
                                            : _toggleTimeline,
                                        child: const Icon(
                                          LucideIcons.film,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                    const Gap(4),
                                    Tooltip(
                                      tooltip: (_) => const Text('State flow'),
                                      child: Button(
                                        key: const ValueKey(
                                          'canvas-state-graph',
                                        ),
                                        style: _showStateGraph
                                            ? const ButtonStyle.primaryIcon()
                                            : const ButtonStyle.ghostIcon(),
                                        onPressed: session == null
                                            ? null
                                            : _toggleGraph,
                                        child: const Icon(
                                          LucideIcons.gitBranch,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                    const Gap(12),
                                    const SizedBox(
                                      height: 20,
                                      child: VerticalDivider(),
                                    ),
                                    const Gap(12),
                                    Tooltip(
                                      tooltip: (_) => Text(
                                        _previewing ? 'Edit canvas' : 'Preview',
                                      ),
                                      child: Button(
                                        key: const ValueKey('canvas-preview'),
                                        style: _previewing
                                            ? const ButtonStyle.primaryIcon()
                                            : const ButtonStyle.ghostIcon(),
                                        onPressed: session == null
                                            ? null
                                            : _togglePreview,
                                        child: Semantics(
                                          label: _previewing
                                              ? 'Edit canvas'
                                              : 'Preview',
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
                              ],
                            ),
                          ),
                        ),
                        if (session != null &&
                            !widget.readOnly &&
                            !_previewing &&
                            _elapsed == null &&
                            session.selectedIds.isNotEmpty &&
                            (session.selectedIds.length > 1 ||
                                session.selectedNode.layout != null)) ...[
                          const Divider(),
                          NodeArrangementToolbar(editor: session),
                        ],
                        const Divider(),
                      ],
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      fit: StackFit.expand,
                      children: [
                        if (!presenting)
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _StudioStageGrid(colors.border),
                            ),
                          ),
                        Padding(
                          key: const ValueKey('canvas-viewport-area'),
                          padding: presenting
                              ? EdgeInsets.zero
                              : EdgeInsets.fromLTRB(
                                  20,
                                  20,
                                  20,
                                  constraints.maxWidth < 720 ? 136 : 88,
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
                                              _responsiveSize != null ||
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
                                          onPrepareGuide: session.tryApplyDraft,
                                          onCreateGuide: session.createGuide,
                                          onUpdateGuide: session.updateGuide,
                                          onDeleteGuide: session.deleteGuide,
                                          assetImageResolver:
                                              widget.assetImageResolver,
                                          assetSvgLoader: widget.assetSvgLoader,
                                          assetFontLoader:
                                              widget.assetFontLoader,
                                          shaderLoader: widget.shaderLoader,
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
                                            if (!session.tryApplyDraft()) {
                                              return null;
                                            }
                                            return session.document.nodes
                                                .firstWhere(
                                                  (node) => node.id == id,
                                                );
                                          },
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
                                          shaderLoader: widget.shaderLoader,
                                        ),
                                    ],
                                  ),
                                ),
                        ),
                        if (!presenting)
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 16,
                            child: _buildCanvasDock(session),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!presenting &&
                    (_responsiveSize != null ||
                        _showStateGraph ||
                        _elapsed != null))
                  ColoredBox(
                    color: colors.background,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_responsiveSize != null) ...[
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
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
                                                      value.value
                                                          .roundToDouble(),
                                                      _responsiveSize!.height,
                                                    )
                                                  : Size(
                                                      _responsiveSize!.width,
                                                      value.value
                                                          .roundToDouble(),
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
                        ],
                        if (session != null && _showStateGraph) ...[
                          const Divider(),
                          StudioStateGraph(
                            editor: session,
                            dormant: widget.dormant,
                            scenario: _scenario,
                            onSelect: (dormant, scenario) {
                              if (dormant != widget.dormant) {
                                widget.onToggleDormant();
                              }
                              setState(() => _scenario = scenario);
                            },
                          ),
                        ],
                        if (session != null && _elapsed != null) ...[
                          const Divider(),
                          StudioTimeline(
                            editor: session,
                            fallbackDuration:
                                widget.theme.bundle.tokens.mediumMotion,
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
                      ],
                    ),
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
      for (final rule in node.transitions) {
        final timing = getSceneMotionDuration(
          node.copyWith(
            tracks: const [],
            motionTiming: rule.timing.isDefault
                ? node.motionTiming
                : rule.timing,
          ),
          widget.theme.tokens.mediumMotion,
        );
        if (timing > duration) duration = timing;
      }
    }
    return duration;
  }
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
