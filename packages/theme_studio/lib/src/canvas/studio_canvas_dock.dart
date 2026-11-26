import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../authoring/scene_editor.dart';
import '../model/studio_canvas_presets.dart';
import '../model/studio_input.dart';
import '../ui/studio_form.dart';
import '../ui/studio_tooltip.dart';

const studioCompactDockWidth = 720.0;

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
                _DockToolGroup(
                  hasSession: hasSession,
                  canEdit: canEdit,
                  tool: tool,
                  handTool: handTool,
                  snapToGuides: snapToGuides,
                  input: input,
                  onSelectTool: onSelectTool,
                  onToggleHand: onToggleHand,
                  onToggleGuides: onToggleGuides,
                  onOpenToolMenu: _openToolMenu,
                ),
                if (!compact)
                  const SizedBox(height: 20, child: VerticalDivider()),
                if (session case final activeSession?)
                  _DockResolutionSelect(
                    session: activeSession,
                    readOnly: readOnly,
                    onSelectPreset: onSelectPreset,
                  ),
                _DockResponsiveToggle(
                  hasSession: hasSession,
                  compact: compact,
                  responsiveActive: responsiveActive,
                  onToggleResponsive: onToggleResponsive,
                ),
                if (!compact)
                  const SizedBox(height: 20, child: VerticalDivider()),
                _DockViewModeSwitch(
                  hasSession: hasSession,
                  comparing: comparing,
                  onToggleComparison: onToggleComparison,
                ),
                if (!compact)
                  const SizedBox(height: 20, child: VerticalDivider()),
                _DockZoomGroup(
                  hasSession: hasSession,
                  zoom: zoom,
                  onZoomOut: onZoomOut,
                  onFitView: onFitView,
                  onZoomIn: onZoomIn,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DockToolGroup extends StatelessWidget {
  const _DockToolGroup({
    required this.hasSession,
    required this.canEdit,
    required this.tool,
    required this.handTool,
    required this.snapToGuides,
    required this.input,
    required this.onSelectTool,
    required this.onToggleHand,
    required this.onToggleGuides,
    required this.onOpenToolMenu,
  });

  final bool hasSession;
  final bool canEdit;
  final StudioCanvasTool tool;
  final bool handTool;
  final bool snapToGuides;
  final StudioInputBindings input;
  final ValueChanged<StudioCanvasTool> onSelectTool;
  final VoidCallback onToggleHand;
  final VoidCallback onToggleGuides;
  final ValueChanged<BuildContext> onOpenToolMenu;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _DockButton(
        id: 'tool-${tool.name}',
        label:
            '${tool.label} · ${input.getBinding(tool.command)?.getLabel() ?? 'Unbound'}',
        icon: StudioCanvasDock._getToolIcon(tool),
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
          onPressed: hasSession ? () => onOpenToolMenu(context) : null,
        ),
      ),
    ],
  );
}

class _DockResolutionSelect extends StatelessWidget {
  const _DockResolutionSelect({
    required this.session,
    required this.readOnly,
    required this.onSelectPreset,
  });

  final SceneEditor session;
  final bool readOnly;
  final ValueChanged<StudioCanvasPreset> onSelectPreset;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final canvas = session.document.canvas;
      return SizedBox(
        width: 132,
        child: StudioSelect<StudioCanvasPreset>(
          above: true,
          theme: SelectTheme(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: (context, states, value) =>
                ButtonVariance.ghost.decoration(context, states),
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
          formatValue: (preset) => '${preset.width} × ${preset.height}',
          onChanged: onSelectPreset,
        ),
      );
    },
  );
}

class _DockResponsiveToggle extends StatelessWidget {
  const _DockResponsiveToggle({
    required this.hasSession,
    required this.compact,
    required this.responsiveActive,
    required this.onToggleResponsive,
  });

  final bool hasSession;
  final bool compact;
  final bool responsiveActive;
  final VoidCallback onToggleResponsive;

  @override
  Widget build(BuildContext context) => StudioTooltip(
    above: true,
    enabled: compact,
    tooltip: (_) => const Text('Responsive viewport'),
    child: Semantics(
      label: 'Responsive',
      toggled: responsiveActive,
      child: Toggle(
        key: const ValueKey('canvas-responsive'),
        value: responsiveActive,
        onChanged: hasSession ? (_) => onToggleResponsive() : null,
        style: const ButtonStyle.ghost(density: ButtonDensity.dense),
        child: compact
            ? const Icon(LucideIcons.monitor, size: 16)
            : const Text('Responsive').small(),
      ),
    ),
  );
}

class _DockViewModeSwitch extends StatelessWidget {
  const _DockViewModeSwitch({
    required this.hasSession,
    required this.comparing,
    required this.onToggleComparison,
  });

  final bool hasSession;
  final bool comparing;
  final VoidCallback onToggleComparison;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
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
                tooltip: (_) =>
                    Text(isCompare ? 'Compare view' : 'Single view'),
                child: Semantics(
                  label: isCompare ? 'Compare' : 'Single',
                  selected: comparing == isCompare,
                  child: Button(
                    key: ValueKey(
                      isCompare ? 'canvas-view-compare' : 'canvas-view-single',
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
    );
  }
}

class _DockZoomGroup extends StatelessWidget {
  const _DockZoomGroup({
    required this.hasSession,
    required this.zoom,
    required this.onZoomOut,
    required this.onFitView,
    required this.onZoomIn,
  });

  final bool hasSession;
  final double? zoom;
  final VoidCallback onZoomOut;
  final VoidCallback onFitView;
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) {
    final activeZoom = zoom;
    return Row(
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
          text: activeZoom == null ? 'Fit' : '${(activeZoom * 100).round()}%',
          onPressed: hasSession ? onFitView : null,
        ),
        _DockButton(
          id: 'zoom-in',
          label: 'Zoom in',
          icon: LucideIcons.plus,
          onPressed: hasSession ? onZoomIn : null,
        ),
      ],
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
