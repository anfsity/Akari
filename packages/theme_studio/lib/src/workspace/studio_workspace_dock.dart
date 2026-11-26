import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../model/studio_workspace_layout.dart';
import '../ui/studio_form.dart';
import '../ui/studio_tooltip.dart';

String getWorkspacePanelLabel(String title) =>
    title == 'Sidebar' ? 'Project' : 'Properties';

class WorkspaceActionButton extends StatelessWidget {
  const WorkspaceActionButton({
    required this.id,
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => StudioTooltip(
    tooltip: (_) => Text(label),
    child: GhostButton(
      key: ValueKey(id),
      onPressed: onPressed,
      density: ButtonDensity.icon,
      child: Icon(icon, size: 16),
    ),
  );
}

class WorkspaceModeControls extends StatelessWidget {
  const WorkspaceModeControls({
    required this.mode,
    required this.presentationLabel,
    required this.onPresetChanged,
    required this.onTogglePresentation,
    super.key,
  });

  final StudioWorkspaceMode mode;
  final String presentationLabel;
  final ValueChanged<StudioWorkspaceMode> onPresetChanged;
  final VoidCallback onTogglePresentation;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 148,
        child: StudioEnumSelect(
          key: const ValueKey('workspace-preset'),
          value: mode,
          values: StudioWorkspaceMode.values,
          formatValue: (value) =>
              '${value.name[0].toUpperCase()}${value.name.substring(1)} layout',
          onChanged: onPresetChanged,
        ),
      ),
      const Gap(4),
      WorkspaceActionButton(
        id: 'presentation-mode',
        label: presentationLabel,
        icon: LucideIcons.maximize,
        onPressed: onTogglePresentation,
      ),
    ],
  );
}

class WorkspaceTopBar extends StatelessWidget {
  const WorkspaceTopBar({
    required this.toolbar,
    required this.onToggleSidebar,
    this.workspaceControls,
    super.key,
  });

  final Widget toolbar;
  final Widget? workspaceControls;
  final VoidCallback onToggleSidebar;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Gap(8),
      WorkspaceActionButton(
        id: 'toggle-sidebar',
        label: 'Toggle project panel',
        icon: LucideIcons.panelLeft,
        onPressed: onToggleSidebar,
      ),
      Expanded(child: toolbar),
      if (workspaceControls case final controls?) ...[controls, const Gap(12)],
    ],
  );
}

class WorkspaceDockPanel extends StatelessWidget {
  const WorkspaceDockPanel({
    required this.controller,
    required this.side,
    required this.presenting,
    required this.panels,
    required this.visible,
    required this.active,
    required this.railPanels,
    required this.contents,
    required this.onSelectTab,
    required this.onFloat,
    required this.onTogglePanel,
    super.key,
  });

  final AbsoluteResizablePaneController controller;
  final StudioDock side;
  final bool presenting;
  final List<String> panels;
  final List<String> visible;
  final String? active;
  final List<String> railPanels;
  final Map<String, Widget> contents;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onFloat;
  final ValueChanged<String> onTogglePanel;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: controller.value,
        maxWidth: controller.value,
        child: Visibility(
          visible: !controller.collapsed,
          maintainState: true,
          child: Column(
            children: [
              if (active case final current? when !presenting) ...[
                _DockHeader(
                  active: current,
                  visible: visible,
                  side: side,
                  onSelectTab: onSelectTab,
                  onFloat: () => onFloat(current),
                  onCollapse: () => onTogglePanel(current),
                ),
                const Divider(),
              ],
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    for (final title in panels)
                      Offstage(
                        offstage: active != title || presenting,
                        child: contents[title]!,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      if (controller.collapsed && !presenting)
        _CollapsedDockRail(
          side: side,
          railPanels: railPanels,
          onReopen: onTogglePanel,
        ),
    ],
  );
}

class _DockHeader extends StatelessWidget {
  const _DockHeader({
    required this.active,
    required this.visible,
    required this.side,
    required this.onSelectTab,
    required this.onFloat,
    required this.onCollapse,
  });

  final String active;
  final List<String> visible;
  final StudioDock side;
  final ValueChanged<String> onSelectTab;
  final VoidCallback onFloat;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: Row(
      children: [
        Expanded(
          child: visible.length > 1
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      for (var i = 0; i < visible.length; i++) ...[
                        if (i > 0) const Gap(2),
                        Expanded(
                          child: Button(
                            key: ValueKey('dock-tab-${visible[i]}'),
                            style: active == visible[i]
                                ? const ButtonStyle.secondary(
                                    density: ButtonDensity.dense,
                                  )
                                : const ButtonStyle.ghost(
                                    density: ButtonDensity.dense,
                                  ),
                            onPressed: () => onSelectTab(visible[i]),
                            child: Text(
                              getWorkspacePanelLabel(visible[i]),
                              overflow: TextOverflow.ellipsis,
                            ).small(),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: onCollapse,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: Text(getWorkspacePanelLabel(active))
                        .small()
                        .semiBold(),
                  ),
                ),
        ),
        WorkspaceActionButton(
          id: 'float-$active',
          label: 'Float panel',
          icon: LucideIcons.externalLink,
          onPressed: onFloat,
        ),
        if (active == 'Inspector')
          WorkspaceActionButton(
            id: 'toggle-inspector',
            label: 'Collapse panel',
            icon: side == StudioDock.left
                ? LucideIcons.panelLeft
                : LucideIcons.panelRight,
            onPressed: onCollapse,
          ),
      ],
    ),
  );
}

class _CollapsedDockRail extends StatelessWidget {
  const _CollapsedDockRail({
    required this.side,
    required this.railPanels,
    required this.onReopen,
  });

  final StudioDock side;
  final List<String> railPanels;
  final ValueChanged<String> onReopen;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Column(
      children: [
        for (final title in railPanels)
          WorkspaceActionButton(
            id: title == 'Sidebar' ? 'reopen-sidebar' : 'toggle-inspector',
            label: 'Show ${getWorkspacePanelLabel(title).toLowerCase()} panel',
            icon: side == StudioDock.left
                ? LucideIcons.panelLeft
                : LucideIcons.panelRight,
            onPressed: () => onReopen(title),
          ),
      ],
    ),
  );
}
