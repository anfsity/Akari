import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'node_inspector_controller.dart';
import 'studio_form.dart';
import 'scene_editor.dart';
import 'node_layout_inspector.dart';
import 'node_style_inspector.dart';
import 'node_motion_inspector.dart';
import 'node_state_inspector.dart';
import 'node_asset_inspector.dart';

class NodeInspector extends StatelessWidget {
  const NodeInspector({
    required this.controller,
    required this.componentCatalog,
    required this.onApply,
    this.editor,
    super.key,
  });

  final NodeInspectorController controller;
  final ThemeComponentCatalog componentCatalog;
  final VoidCallback onApply;
  final SceneEditor? editor;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => editor?.selectedIds.isEmpty == true
        ? const Center(child: Text('Select a layer to edit.'))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InspectorHeader(
                node: controller.node,
                definition:
                    componentCatalog.components[controller.node.componentId],
              ),
              const Divider(),
              Expanded(
                child: _InspectorForm(
                  controller: controller,
                  definition:
                      componentCatalog.components[controller.node.componentId],
                  onApply: onApply,
                  editor: editor,
                ),
              ),
              const Divider(),
              _InspectorActions(
                hasDraft: controller.hasDraft,
                error: controller.error,
                onApply: onApply,
              ),
            ],
          ),
  );
}

class _InspectorHeader extends StatelessWidget {
  const _InspectorHeader({required this.node, required this.definition});

  final SceneNode node;
  final ThemeComponentDefinition? definition;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          node.id,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ).small().semiBold(),
        Text(
          definition?.label ?? node.componentId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ).muted().xSmall(),
      ],
    ),
  );
}

class _InspectorForm extends StatelessWidget {
  const _InspectorForm({
    required this.controller,
    required this.definition,
    required this.onApply,
    required this.editor,
  });

  final NodeInspectorController controller;
  final ThemeComponentDefinition? definition;
  final VoidCallback onApply;
  final SceneEditor? editor;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('node-inspector-form'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: switch (editor) {
            final session? when controller.node.asset != null =>
              NodeAssetInspector(editor: session),
            _ => _InspectorProperties(
              controller: controller,
              definition: definition,
              onApply: onApply,
            ),
          },
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: _buildLayoutSection(),
        ),
        const Divider(),
        if (editor case final session?) ...[
          NodeLayoutInspector(editor: session),
          const Divider(),
          StudioDisclosureSection(
            title: 'Visual style',
            child: NodeStyleInspector(editor: session),
          ),
          const Divider(),
          StudioDisclosureSection(
            title: 'State rules',
            child: NodeStateInspector(editor: session),
          ),
          const Divider(),
        ],
        StudioDisclosureSection(
          title: 'Advanced layout',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              _buildLayeringSection(),
              const Divider(),
              _buildTransformSection(),
              const Divider(),
              _buildMotionSection(),
            ],
          ),
        ),
        const Divider(),
        StudioDisclosureSection(
          title: 'Advanced properties',
          child: _buildField('Properties', maxLines: 6),
        ),
        const Divider(),
      ],
    ),
  );

  static const _prefixes = <String, String>{
    'X': 'X',
    'Y': 'Y',
    'Width': 'W',
    'Height': 'H',
    'Rotate Z': '∠',
    'Depth': 'Z',
    'Paint order': 'Paint',
    'Focus order': 'Focus',
    'Translate X': 'TX',
    'Translate Y': 'TY',
    'Scale X': 'SX',
    'Scale Y': 'SY',
    'Rotate X': 'RX',
    'Rotate Y': 'RY',
    'Pivot X': 'PX',
    'Pivot Y': 'PY',
    'Perspective': 'Persp',
  };

  Widget _buildLayoutSection() => StudioFormSection(
    title: 'Layout',
    trailing: StudioEnumSelect(
      value: controller.layoutUnit,
      values: StudioLayoutUnit.values,
      formatValue: (unit) =>
          unit == StudioLayoutUnit.pixels ? 'Pixels' : 'Percent',
      onChanged: controller.updateLayoutUnit,
    ),
    spacing: 8,
    children: [
      _buildPair('X', 'Y'),
      _buildPair('Width', 'Height'),
      StudioFieldRow(
        left: _buildField('Rotate Z'),
        right: const SizedBox.shrink(),
      ),
    ],
  );

  Widget _buildLayeringSection() => StudioFormSection(
    title: 'Layering',
    spacing: 8,
    children: [_buildField('Depth'), _buildPair('Paint order', 'Focus order')],
  );

  Widget _buildTransformSection() => StudioFormSection(
    title: 'Transform',
    spacing: 8,
    children: [
      _buildPair('Translate X', 'Translate Y'),
      _buildPair('Scale X', 'Scale Y'),
      OutlineButton(
        key: const ValueKey('reset-node-scale'),
        density: ButtonDensity.dense,
        onPressed: () {
          controller.resetScale();
          onApply();
        },
        child: const Text('Reset scale').small(),
      ),
      _buildPair('Rotate X', 'Rotate Y'),
      _buildPair('Pivot X', 'Pivot Y'),
      _buildField('Perspective'),
    ],
  );

  Widget _buildMotionSection() => StudioFormSection(
    title: 'Motion',
    headerSpacing: 8,
    spacing: 8,
    children: [
      StudioEnumSelect(
        value: controller.motion,
        values: SceneMotionPreset.values,
        onChanged: (motion) {
          controller.updateMotion(motion);
          onApply();
        },
      ),
      if (editor case final session?) NodeMotionInspector(editor: session),
    ],
  );

  Widget _buildPair(String left, String right) =>
      StudioFieldRow(left: _buildField(left), right: _buildField(right));

  Widget _buildField(String label, {int maxLines = 1}) => StudioFormField(
    label: label,
    prefix: _prefixes[label],
    inputKey: ValueKey('field-$label'),
    controller: controller.getField(label),
    maxLines: maxLines,
    onSubmitted: maxLines == 1 ? onApply : null,
    onFocusLost: onApply,
  );
}

class _InspectorProperties extends StatelessWidget {
  const _InspectorProperties({
    required this.controller,
    required this.definition,
    required this.onApply,
  });

  final NodeInspectorController controller;
  final ThemeComponentDefinition? definition;
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
      // Undeclared components retain their existing raw string editor. For an
      // opted-in component only its author-declared controls appear here;
      // additional properties remain intact in Advanced properties.
      final definitions =
          definition?.properties ??
          [
            for (final entry in properties.entries)
              ThemeTextProperty(
                name: entry.key,
                label: entry.key,
                defaultValue: entry.value,
              ),
          ];
      return StudioFormSection(
        title: 'Component properties',
        children: [
          if (definitions.isEmpty)
            const Text('This component has no editable properties.')
                .small()
                .muted()
          else
            _PropertyRows(
              key: ValueKey(controller.node.id),
              properties: properties,
              definitions: definitions,
              onChanged: controller.updateProperty,
              onApply: onApply,
            ),
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
    required this.definitions,
    required this.onChanged,
    required this.onApply,
    super.key,
  });

  final Map<String, String> properties;
  final List<ThemeProperty<Object>> definitions;
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
    final definitions = widget.definitions.whereType<ThemeTextProperty>();
    final active = definitions.map((property) => property.name).toSet();
    _fields.removeWhere((key, controller) {
      if (!active.contains(key)) {
        controller.dispose();
        return true;
      }
      return false;
    });
    for (final property in definitions) {
      final field = _fields.putIfAbsent(
        property.name,
        TextEditingController.new,
      );
      final value = property.getValue(widget.properties);
      if (field.text != value) field.text = value;
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
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 10,
    children: [
      for (final property in widget.definitions)
        switch (property) {
          ThemeTextProperty() => StudioFormField(
            label: property.label,
            inputKey: ValueKey('property-${property.name}'),
            controller: _fields[property.name]!,
            onChanged: (value) {
              // shadcn also emits changes while controllers are synchronized.
              // Projecting an omitted default must never create a JSON draft.
              if (value == property.getValue(widget.properties)) return;
              widget.onChanged(property.name, value);
            },
            onSubmitted: widget.onApply,
            onFocusLost: widget.onApply,
          ),
          ThemeChoiceProperty() => _buildChoice(property),
        },
    ],
  );

  Widget _buildChoice(ThemeChoiceProperty<Enum> property) {
    Enum? value;
    try {
      value = property.getValue(widget.properties);
    } on FormatException {
      // A raw JSON draft may contain an unsupported choice. Keep the selector
      // available to repair it while the canvas retains its last valid scene.
      value = null;
    }
    return StudioLabeledField(
      label: property.label,
      child: StudioSelect<Enum>(
        key: ValueKey('property-${property.name}'),
        value: value,
        values: property.choices.keys,
        formatValue: (choice) => property.choices[choice]!,
        placeholder: const Text('Choose a valid option'),
        onChanged: (choice) {
          widget.onChanged(property.name, choice.name);
          widget.onApply();
        },
      ),
    );
  }
}

class _InspectorActions extends StatelessWidget {
  const _InspectorActions({
    required this.hasDraft,
    required this.error,
    required this.onApply,
  });

  final bool hasDraft;
  final String? error;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final active = hasDraft || error != null;
    return Padding(
      key: const ValueKey('inspector-actions'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error case final message?) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 64),
              child: SingleChildScrollView(child: StudioFormError(message)),
            ),
            const Gap(6),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  error != null
                      ? 'Validation error'
                      : hasDraft
                      ? 'Pending draft'
                      : 'Synced',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).xSmall().muted(),
              ),
              Button(
                style: active
                    ? const ButtonStyle.primary(density: ButtonDensity.dense)
                    : const ButtonStyle.ghost(density: ButtonDensity.dense),
                onPressed: onApply,
                child: active
                    ? const Text('Apply to preview').xSmall()
                    : const Text('Apply to preview').xSmall().muted(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
