import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../model/studio_canvas_presets.dart';
import '../model/studio_input.dart';
import '../model/studio_scenario.dart';
import '../timeline/studio_state_graph.dart';
import '../timeline/studio_timeline.dart';
import '../ui/studio_form.dart';
import '../ui/studio_tooltip.dart';
import 'node_arrangement_toolbar.dart';

const studioCompactDockWidth = 720.0;

Duration getStudioTimelineDuration(
  SceneEditor session,
  Duration fallbackDuration,
) {
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

class StudioCanvasTopBar extends StatelessWidget {
  const StudioCanvasTopBar({
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
    super.key,
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

class StudioCanvasDock extends StatelessWidget {
  const StudioCanvasDock({
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
    required this.onActualSize,
    required this.onZoomIn,
    super.key,
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
  final VoidCallback onActualSize;
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
          MenuButton(
            key: const ValueKey('zoom-actual-size'),
            leading: const Icon(LucideIcons.scan, size: 16),
            trailing: Text(
              input.getBinding(StudioCommand.actualSize)?.getLabel() ??
                  'Unbound',
            ).xSmall().muted(),
            onPressed: (_) => onActualSize(),
            child: const Text('Actual size'),
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
        final compact = constraints.maxWidth < studioCompactDockWidth;
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

class StudioCanvasBottomDrawer extends StatelessWidget {
  const StudioCanvasBottomDrawer({
    required this.session,
    required this.readOnly,
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
    super.key,
  });

  final SceneEditor? session;
  final bool readOnly;
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
                      readOnly: readOnly,
                      dormant: dormant,
                      scenario: scenario,
                      onSelect: onSelectState,
                    ),
                  ],
                  if (elapsed case final activeElapsed?) ...[
                    const Divider(),
                    StudioTimeline(
                      editor: activeSession,
                      readOnly: readOnly,
                      fallbackDuration: fallbackDuration,
                      duration: getStudioTimelineDuration(
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
