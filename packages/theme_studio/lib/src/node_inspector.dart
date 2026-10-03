import 'package:scene/scene.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'node_inspector_controller.dart';
import 'studio_form.dart';

class NodeInspector extends StatelessWidget {
  const NodeInspector({
    required this.controller,
    required this.onApply,
    super.key,
  });

  final NodeInspectorController controller;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ResizablePanel.vertical(
      key: const ValueKey('inspector-panels'),
      draggerThickness: 10,
      children: [
        ResizablePane(
          key: const ValueKey('inspector-header-pane'),
          initialSize: 80,
          minSize: 80,
          maxSize: 140,
          child: _InspectorHeader(node: controller.node),
        ),
        ResizablePane.flex(
          minSize: 200,
          child: _InspectorForm(controller: controller, onApply: onApply),
        ),
        ResizablePane(
          key: const ValueKey('inspector-actions-pane'),
          initialSize: 120,
          minSize: 120,
          maxSize: 180,
          child: _InspectorActions(error: controller.error, onApply: onApply),
        ),
      ],
    ),
  );
}

class _InspectorHeader extends StatelessWidget {
  const _InspectorHeader({required this.node});

  final SceneNode node;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(node.id).semiBold(),
        Text(node.componentId).muted().small(),
      ],
    ),
  );
}

enum _InspectorSection { layout, layering, transform, motion, properties }

class _InspectorForm extends StatelessWidget {
  const _InspectorForm({required this.controller, required this.onApply});

  final NodeInspectorController controller;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(16),
    itemCount: _InspectorSection.values.length,
    separatorBuilder: (context, index) => const Gap(12),
    itemBuilder: (context, index) => switch (_InspectorSection.values[index]) {
      _InspectorSection.layout => _buildLayoutSection(),
      _InspectorSection.layering => _buildLayeringSection(),
      _InspectorSection.transform => _buildTransformSection(),
      _InspectorSection.motion => _buildMotionSection(),
      _InspectorSection.properties => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _buildField('Properties', maxLines: 6),
      ),
    },
  );

  Widget _buildLayoutSection() => StudioFormSection(
    title: 'Layout · normalized 0–1',
    compact: true,
    children: [_buildPair('X', 'Y'), _buildPair('Width', 'Height')],
  );

  Widget _buildLayeringSection() => StudioFormSection(
    title: 'Layering',
    compact: true,
    children: [_buildField('Depth'), _buildPair('Paint order', 'Focus order')],
  );

  Widget _buildTransformSection() => StudioFormSection(
    title: 'Transform',
    compact: true,
    children: [
      _buildPair('Translate X', 'Translate Y'),
      _buildPair('Scale X', 'Scale Y'),
      _buildPair('Rotate X', 'Rotate Y'),
      _buildField('Rotate Z'),
      _buildPair('Pivot X', 'Pivot Y'),
      _buildField('Perspective'),
    ],
  );

  Widget _buildMotionSection() => StudioFormSection(
    title: 'Motion',
    compact: true,
    headerSpacing: 8,
    children: [
      StudioEnumSelect(
        value: controller.motion,
        values: SceneMotionPreset.values,
        onChanged: controller.updateMotion,
      ),
    ],
  );

  Widget _buildPair(String left, String right) =>
      StudioFieldRow(left: _buildField(left), right: _buildField(right));

  Widget _buildField(String label, {int maxLines = 1}) => StudioFormField(
    label: label,
    inputKey: ValueKey('field-$label'),
    controller: controller.getField(label),
    maxLines: maxLines,
    onSubmitted: maxLines == 1 ? onApply : null,
  );
}

class _InspectorActions extends StatelessWidget {
  const _InspectorActions({required this.error, required this.onApply});

  final String? error;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error case final message?) ...[
          StudioFormError(message),
          const Gap(12),
        ],
        PrimaryButton(
          onPressed: onApply,
          child: const Text('Apply to preview'),
        ),
      ],
    ),
  );
}
