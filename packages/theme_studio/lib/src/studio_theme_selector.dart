import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'studio_theme_project.dart';

class StudioThemeSelector extends StatefulWidget {
  const StudioThemeSelector({
    required this.projects,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<StudioThemeProject> projects;
  final StudioThemeProject selected;
  final ValueChanged<StudioThemeProject> onChanged;

  @override
  State<StudioThemeSelector> createState() => _StudioThemeSelectorState();
}

class _StudioThemeSelectorState extends State<StudioThemeSelector> {
  final _anchor = Object();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('THEME').small().muted(),
        const Gap(8),
        // A linked anchor follows panel movement through compositing. The
        // default context anchor polls every frame while the menu is open.
        OverlayAnchor(
          anchor: _anchor,
          child: Select<StudioThemeProject>(
            key: const ValueKey('studio-theme-select'),
            theme: const SelectTheme(adaptiveOverlay: false),
            overlayConfiguration: PopoverConfiguration(
              anchor: LinkedAnchor(_anchor),
              alignment: Alignment.topCenter,
              widthConstraint: PopoverConstraint.anchorFixedSize,
              offset: const Offset(0, 4),
            ),
            value: widget.selected,
            onChanged: (project) {
              if (project != null && !identical(project, widget.selected)) {
                widget.onChanged(project);
              }
            },
            itemBuilder: (context, project) => Text(project.packageName),
            popup: SelectPopup(
              items: SelectItemList(
                children: [
                  for (final project in widget.projects)
                    SelectItemButton(
                      value: project,
                      child: Text(project.packageName),
                    ),
                ],
              ),
            ).call,
          ),
        ),
      ],
    ),
  );
}
