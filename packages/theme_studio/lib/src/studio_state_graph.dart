import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'studio_preview_host.dart';

class StudioStateGraph extends StatelessWidget {
  const StudioStateGraph({
    required this.dormant,
    required this.scenario,
    required this.onSelect,
    super.key,
  });
  final bool dormant;
  final StudioPreviewScenario scenario;
  final void Function(bool, StudioPreviewScenario) onSelect;

  Widget _state(String label, bool dormant, StudioPreviewScenario scenario) =>
      Button(
        key: ValueKey('graph-$label'),
        style: this.dormant == dormant && (dormant || this.scenario == scenario)
            ? const ButtonStyle.primary()
            : const ButtonStyle.outline(),
        onPressed: () => onSelect(dormant, scenario),
        child: Text(label),
      );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('State flow · Select a state to preview').small().semiBold(),
        const Gap(8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _state('Dormant', true, StudioPreviewScenario.password),
              const Icon(LucideIcons.arrowRight, size: 16),
              _state('Login', false, StudioPreviewScenario.password),
              const Icon(LucideIcons.arrowRight, size: 16),
              _state('Submitting', false, StudioPreviewScenario.submitting),
              const Icon(LucideIcons.arrowRight, size: 16),
              Column(
                children: [
                  _state('Success', false, StudioPreviewScenario.success),
                  const Gap(4),
                  _state('Error', false, StudioPreviewScenario.error),
                ],
              ),
            ],
          ),
        ),
        const Gap(8),
        const Text(
          'Select a layer, then open State rules in Design to author visibility and state-entry responses.',
        ).small().muted(),
      ],
    ),
  );
}
