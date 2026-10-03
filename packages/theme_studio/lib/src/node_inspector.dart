import 'package:scene/scene.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'node_inspector_controller.dart';

class NodeInspector extends StatelessWidget {
  const NodeInspector({
    required this.controller,
    required this.onApply,
    super.key,
  });

  final NodeInspectorController controller;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(controller.node.id).semiBold(),
                Text(controller.node.componentId).muted().small(),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Layout · normalized 0–1').small().semiBold(),
                const Gap(12),
                _buildPair('X', 'Y'),
                _buildPair('Width', 'Height'),
                const Gap(12),
                const Text('Layering').small().semiBold(),
                const Gap(12),
                _buildField('Depth'),
                _buildPair('Paint order', 'Focus order'),
                const Gap(12),
                const Text('Transform').small().semiBold(),
                const Gap(12),
                _buildPair('Translate X', 'Translate Y'),
                _buildPair('Scale X', 'Scale Y'),
                _buildPair('Rotate X', 'Rotate Y'),
                _buildField('Rotate Z'),
                _buildPair('Pivot X', 'Pivot Y'),
                _buildField('Perspective'),
                const Gap(12),
                const Text('Motion').small().semiBold(),
                const Gap(8),
                Select<SceneMotionPreset>(
                  value: controller.motion,
                  onChanged: (value) {
                    if (value != null) controller.updateMotion(value);
                  },
                  itemBuilder: (context, value) => Text(value.name),
                  popup: SelectPopup(
                    items: SelectItemList(
                      children: [
                        for (final motion in SceneMotionPreset.values)
                          SelectItemButton(
                            value: motion,
                            child: Text(motion.name),
                          ),
                      ],
                    ),
                  ).call,
                ),
                const Gap(20),
                _buildField('Properties', maxLines: 6),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (controller.error != null) ...[
                  Text(
                    controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.destructive,
                    ),
                  ).small(),
                  const Gap(12),
                ],
                PrimaryButton(
                  onPressed: onApply,
                  child: const Text('Apply to preview'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPair(String left, String right) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _buildField(left)),
      const Gap(12),
      Expanded(child: _buildField(right)),
    ],
  );

  Widget _buildField(String label, {int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label).small().muted(),
        const Gap(6),
        Semantics(
          label: label,
          child: TextField(
            key: ValueKey('field-$label'),
            controller: controller.getField(label),
            maxLines: maxLines,
            onSubmitted: maxLines == 1 ? (_) => onApply() : null,
          ),
        ),
      ],
    ),
  );
}
