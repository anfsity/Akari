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
        Text(node.id, maxLines: 1, overflow: TextOverflow.ellipsis).semiBold(),
        Text(
          node.componentId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ).muted().small(),
      ],
    ),
  );
}

class _InspectorForm extends StatelessWidget {
  const _InspectorForm({required this.controller, required this.onApply});

  final NodeInspectorController controller;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLayoutSection(),
        const Divider(),
        const Gap(12),
        _InspectorProperties(controller: controller, onApply: onApply),
        const Divider(),
        const Gap(12),
        _buildMotionSection(),
        const Gap(16),
        _InspectorDisclosure(
          title: 'Advanced layout',
          child: Column(
            children: [
              const Gap(12),
              _buildLayeringSection(),
              _buildTransformSection(),
            ],
          ),
        ),
        const Gap(12),
        _InspectorDisclosure(
          title: 'Advanced properties',
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _buildField('Properties', maxLines: 6),
          ),
        ),
      ],
    ),
  );

  Widget _buildLayoutSection() => StudioFormSection(
    title: 'Layout',
    compact: true,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: StudioEnumSelect(
          value: controller.layoutUnit,
          values: StudioLayoutUnit.values,
          formatValue: (unit) =>
              unit == StudioLayoutUnit.pixels ? 'Pixels' : 'Percent',
          onChanged: controller.updateLayoutUnit,
        ),
      ),
      const Gap(12),
      _buildPair('X', 'Y'),
      _buildPair('Width', 'Height'),
      _buildField('Rotate Z'),
    ],
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
        onChanged: (motion) {
          controller.updateMotion(motion);
          onApply();
        },
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
    onFocusLost: onApply,
  );
}

class _InspectorDisclosure extends StatefulWidget {
  const _InspectorDisclosure({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_InspectorDisclosure> createState() => _InspectorDisclosureState();
}

class _InspectorDisclosureState extends State<_InspectorDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GhostButton(
        onPressed: () => setState(() => _expanded = !_expanded),
        child: Row(
          children: [
            Expanded(child: Text(widget.title).small().semiBold()),
            Icon(
              _expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
              size: 16,
            ),
          ],
        ),
      ),
      if (_expanded) widget.child,
    ],
  );
}

class _InspectorProperties extends StatelessWidget {
  const _InspectorProperties({required this.controller, required this.onApply});

  final NodeInspectorController controller;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller.getField('Properties'),
    builder: (context, _, _) {
      Map<String, String> properties;
      try {
        properties = controller.getPropertiesDraft();
      } on FormatException {
        return const Text(
          'Correct the JSON in Advanced properties to edit component fields.',
        ).small().muted();
      }
      return StudioFormSection(
        title: 'Component properties',
        compact: true,
        children: [
          if (properties.isEmpty)
            const Text('This component has no configured properties.')
                .small()
                .muted()
          else
            _PropertyRows(
              key: ValueKey(controller.node.id),
              properties: properties,
              onChanged: controller.updateProperty,
              onApply: onApply,
            ),
          const Gap(12),
        ],
      );
    },
  );
}

/// Row controllers project the JSON draft; that draft remains the sole source
/// for validation, history and saving. Only external changes replace row text,
/// so typing does not move the caret or recreate the active input.
class _PropertyRows extends StatefulWidget {
  const _PropertyRows({
    required this.properties,
    required this.onChanged,
    required this.onApply,
    super.key,
  });

  final Map<String, String> properties;
  final void Function(String, String) onChanged;
  final VoidCallback onApply;

  @override
  State<_PropertyRows> createState() => _PropertyRowsState();
}

class _PropertyRowsState extends State<_PropertyRows> {
  final _fields = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _updateFields();
  }

  @override
  void didUpdateWidget(_PropertyRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateFields();
  }

  void _updateFields() {
    for (final entry in widget.properties.entries) {
      final field = _fields.putIfAbsent(entry.key, TextEditingController.new);
      if (field.text != entry.value) field.text = entry.value;
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final name in widget.properties.keys)
        StudioFormField(
          label: name,
          inputKey: ValueKey('property-$name'),
          controller: _fields[name]!,
          onChanged: (value) => widget.onChanged(name, value),
          onSubmitted: widget.onApply,
          onFocusLost: widget.onApply,
        ),
    ],
  );
}

class _InspectorActions extends StatelessWidget {
  const _InspectorActions({required this.error, required this.onApply});

  final String? error;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
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
          const Gap(8),
          const Text('Enter or leave a field to apply. Save writes to disk.')
              .small()
              .muted(),
        ],
      ),
    ),
  );
}
