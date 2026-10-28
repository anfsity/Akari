import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'studio_form.dart';
import 'studio_theme_project.dart';

class StudioThemeSelector extends StatelessWidget {
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Theme').small().muted(),
        const Gap(8),
        StudioSelect<StudioThemeProject>(
          key: const ValueKey('studio-theme-select'),
          value: selected,
          values: projects,
          formatValue: (project) => project.packageName,
          onChanged: (project) {
            if (!identical(project, selected)) onChanged(project);
          },
        ),
      ],
    ),
  );
}
