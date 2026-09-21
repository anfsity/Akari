import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import 'condition_editor.dart';
import 'editor_controller.dart';

/// Property panel for the selected node.
class InspectorPanel extends StatelessWidget {
  const InspectorPanel({required this.controller, super.key});

  final SceneEditorController controller;

  @override
  Widget build(BuildContext context) {
    final node = controller.selectedNode;
    if (node == null) {
      return const Center(child: Text('Select a node.'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _Section(
          title: 'Identity',
          children: [
            _IdField(controller: controller, node: node),
            const SizedBox(height: 8),
            _EnumDropdown<SceneNodeKind>(
              label: 'kind',
              value: node.kind,
              values: SceneNodeKind.values,
              onChanged: (value) =>
                  controller.updateSelected((node) => node.copyWith(kind: value)),
            ),
            const SizedBox(height: 8),
            _NullableEnumDropdown<SceneAction>(
              label: 'action',
              value: node.action,
              values: SceneAction.values,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(action: value),
              ),
            ),
            const SizedBox(height: 8),
            _EnumDropdown<SceneMotionPreset>(
              label: 'motion',
              value: node.motion,
              values: SceneMotionPreset.values,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(motion: value),
              ),
            ),
          ],
        ),
        _Section(
          title: 'Rect (normalized)',
          children: [
            _SliderRow(
              label: 'x',
              value: node.rect.x,
              min: 0,
              max: 1,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(rect: node.rect.copyWith(x: value)),
              ),
            ),
            _SliderRow(
              label: 'y',
              value: node.rect.y,
              min: 0,
              max: 1,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(rect: node.rect.copyWith(y: value)),
              ),
            ),
            _SliderRow(
              label: 'width',
              value: node.rect.width,
              min: 0.01,
              max: 1,
              onChanged: (value) => controller.updateSelected(
                (node) =>
                    node.copyWith(rect: node.rect.copyWith(width: value)),
              ),
            ),
            _SliderRow(
              label: 'height',
              value: node.rect.height,
              min: 0.01,
              max: 1,
              onChanged: (value) => controller.updateSelected(
                (node) =>
                    node.copyWith(rect: node.rect.copyWith(height: value)),
              ),
            ),
          ],
        ),
        _Section(
          title: 'Transform',
          children: [
            _SliderRow(
              label: 'rotate Z',
              value: node.transform.rotationZ,
              min: -180,
              max: 180,
              onChanged: (value) => _updateTransform(
                controller,
                node.transform.copyWith(rotationZ: value),
              ),
            ),
            _SliderRow(
              label: 'rotate X',
              value: node.transform.rotationX,
              min: -180,
              max: 180,
              onChanged: (value) => _updateTransform(
                controller,
                node.transform.copyWith(rotationX: value),
              ),
            ),
            _SliderRow(
              label: 'rotate Y',
              value: node.transform.rotationY,
              min: -180,
              max: 180,
              onChanged: (value) => _updateTransform(
                controller,
                node.transform.copyWith(rotationY: value),
              ),
            ),
            _SliderRow(
              label: 'perspective',
              value: node.transform.perspective,
              min: -0.01,
              max: 0.01,
              onChanged: (value) => _updateTransform(
                controller,
                node.transform.copyWith(perspective: value),
              ),
            ),
            _SliderRow(
              label: 'scale X',
              value: node.transform.scaleX,
              min: 0.1,
              max: 3,
              onChanged: (value) => _updateTransform(
                controller,
                node.transform.copyWith(scaleX: value),
              ),
            ),
            _SliderRow(
              label: 'scale Y',
              value: node.transform.scaleY,
              min: 0.1,
              max: 3,
              onChanged: (value) => _updateTransform(
                controller,
                node.transform.copyWith(scaleY: value),
              ),
            ),
            _SliderRow(
              label: 'move X',
              value: node.transform.translateX,
              min: -0.5,
              max: 0.5,
              onChanged: (value) => _updateTransform(
                controller,
                node.transform.copyWith(translateX: value),
              ),
            ),
            _SliderRow(
              label: 'move Y',
              value: node.transform.translateY,
              min: -0.5,
              max: 0.5,
              onChanged: (value) => _updateTransform(
                controller,
                node.transform.copyWith(translateY: value),
              ),
            ),
            _SliderRow(
              label: 'pivot X',
              value: node.transform.pivotX,
              min: 0,
              max: 1,
              onChanged: (value) => _updateTransform(
                controller,
                node.transform.copyWith(pivotX: value),
              ),
            ),
            _SliderRow(
              label: 'pivot Y',
              value: node.transform.pivotY,
              min: 0,
              max: 1,
              onChanged: (value) => _updateTransform(
                controller,
                node.transform.copyWith(pivotY: value),
              ),
            ),
          ],
        ),
        _Section(
          title: 'Layout',
          children: [
            _IntField(
              label: 'z',
              value: node.z,
              onChanged: (value) =>
                  controller.updateSelected((node) => node.copyWith(z: value)),
            ),
            const SizedBox(height: 8),
            _IntField(
              label: 'renderOrder',
              value: node.renderOrder,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(renderOrder: value),
              ),
            ),
            const SizedBox(height: 8),
            _IntField(
              label: 'focusOrder',
              value: node.focusOrder,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(focusOrder: value),
              ),
            ),
          ],
        ),
        _Section(
          title: 'Visibility',
          children: [
            ConditionEditor(
              condition: node.visibleWhen,
              onChanged: (value) => controller.updateSelected(
                (node) => node.copyWith(visibleWhen: value),
              ),
            ),
          ],
        ),
        _Section(
          title: 'Properties',
          children: [
            _PropertiesEditor(controller: controller, node: node),
          ],
        ),
      ],
    );
  }
}

void _updateTransform(SceneEditorController controller, SceneTransform transform) {
  controller.updateSelected((node) => node.copyWith(transform: transform));
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _EnumDropdown<T extends Enum> extends StatelessWidget {
  const _EnumDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        Expanded(
          child: DropdownButton<T>(
            isExpanded: true,
            value: value,
            onChanged: (selected) {
              if (selected != null) {
                onChanged(selected);
              }
            },
            items: [
              for (final option in values)
                DropdownMenuItem(value: option, child: Text(option.name)),
            ],
          ),
        ),
      ],
    );
  }
}

class _NullableEnumDropdown<T extends Enum> extends StatelessWidget {
  const _NullableEnumDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<T> values;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        Expanded(
          child: DropdownButton<T?>(
            isExpanded: true,
            value: value,
            onChanged: onChanged,
            items: [
              const DropdownMenuItem(value: null, child: Text('none')),
              for (final option in values)
                DropdownMenuItem(value: option, child: Text(option.name)),
            ],
          ),
        ),
      ],
    );
  }
}

class _IdField extends StatelessWidget {
  const _IdField({required this.controller, required this.node});

  final SceneEditorController controller;
  final SceneNode node;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey(node.id),
      initialValue: node.id,
      decoration: const InputDecoration(labelText: 'id', isDense: true),
      onFieldSubmitted: (value) {
        final id = value.trim();
        final document = controller.document;
        if (document == null || id.isEmpty) {
          return;
        }
        final taken = document.nodes.any(
          (candidate) => candidate.id == id && candidate.id != node.id,
        );
        if (taken) {
          return;
        }
        controller.updateSelected((node) => node.copyWith(id: id));
      },
    );
  }
}

class _IntField extends StatelessWidget {
  const _IntField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('$label:$value'),
      initialValue: value.toString(),
      decoration: InputDecoration(labelText: label, isDense: true),
      keyboardType: TextInputType.number,
      onFieldSubmitted: (text) {
        final parsed = int.tryParse(text.trim());
        if (parsed != null) {
          onChanged(parsed);
        }
      },
    );
  }
}

class _PropertiesEditor extends StatelessWidget {
  const _PropertiesEditor({required this.controller, required this.node});

  final SceneEditorController controller;
  final SceneNode node;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in node.properties.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(entry.key, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    key: ValueKey('${node.id}:${entry.key}:${entry.value}'),
                    initialValue: entry.value,
                    decoration: const InputDecoration(isDense: true),
                    onFieldSubmitted: (value) => controller.updateSelected(
                      (node) => node.copyWith(
                        properties: {...node.properties, entry.key: value},
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove property',
                  onPressed: () => controller.updateSelected(
                    (node) => node.copyWith(
                      properties: {
                        for (final candidate in node.properties.entries)
                          if (candidate.key != entry.key)
                            candidate.key: candidate.value,
                      },
                    ),
                  ),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: () => controller.updateSelected(
            (node) => node.copyWith(
              properties: {
                ...node.properties,
                _uniqueKey(node.properties, 'property'): '',
              },
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add property'),
        ),
      ],
    );
  }
}

String _uniqueKey(Map<String, String> properties, String base) {
  var index = 1;
  while (properties.containsKey('$base$index')) {
    index++;
  }
  return '$base$index';
}
