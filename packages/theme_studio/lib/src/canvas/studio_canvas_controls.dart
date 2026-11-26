import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../model/studio_scenario.dart';
import '../timeline/studio_state_graph.dart';
import '../timeline/studio_timeline.dart';
import '../ui/studio_form.dart';
import '../ui/studio_tooltip.dart';
import 'node_arrangement_toolbar.dart';

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
                  _CanvasStateControls(
                    dormant: dormant,
                    scenario: scenario,
                    timelineOpen: timelineOpen,
                    onToggleDormant: onToggleDormant,
                    onSelectScenario: onSelectScenario,
                  ),
                  _CanvasModeButtons(
                    hasSession: hasSession,
                    timelineOpen: timelineOpen,
                    showStateGraph: showStateGraph,
                    previewing: previewing,
                    onToggleTimeline: onToggleTimeline,
                    onToggleGraph: onToggleGraph,
                    onTogglePreview: onTogglePreview,
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

class _CanvasStateControls extends StatelessWidget {
  const _CanvasStateControls({
    required this.dormant,
    required this.scenario,
    required this.timelineOpen,
    required this.onToggleDormant,
    required this.onSelectScenario,
  });

  final bool dormant;
  final StudioPreviewScenario scenario;
  final bool timelineOpen;
  final VoidCallback onToggleDormant;
  final ValueChanged<StudioPreviewScenario> onSelectScenario;

  @override
  Widget build(BuildContext context) => Wrap(
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
            child: Text(dormant ? 'State: Dormant' : 'State: Login').small(),
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
  );
}

class _CanvasModeButtons extends StatelessWidget {
  const _CanvasModeButtons({
    required this.hasSession,
    required this.timelineOpen,
    required this.showStateGraph,
    required this.previewing,
    required this.onToggleTimeline,
    required this.onToggleGraph,
    required this.onTogglePreview,
  });

  final bool hasSession;
  final bool timelineOpen;
  final bool showStateGraph;
  final bool previewing;
  final VoidCallback onToggleTimeline;
  final VoidCallback onToggleGraph;
  final VoidCallback onTogglePreview;

  @override
  Widget build(BuildContext context) => Row(
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
        tooltip: (_) => Text(previewing ? 'Edit canvas' : 'Preview'),
        child: Button(
          key: const ValueKey('canvas-preview'),
          style: previewing
              ? const ButtonStyle.primaryIcon()
              : const ButtonStyle.ghostIcon(),
          onPressed: hasSession ? onTogglePreview : null,
          child: Semantics(
            label: previewing ? 'Edit canvas' : 'Preview',
            child: Icon(
              previewing ? LucideIcons.mousePointer2 : LucideIcons.play,
              size: 16,
            ),
          ),
        ),
      ),
    ],
  );
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
