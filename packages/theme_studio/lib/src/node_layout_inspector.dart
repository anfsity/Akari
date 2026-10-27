import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_form.dart';
import 'studio_form_values.dart';

/// Frame and sizing edits use the same validated document command as geometry.
class NodeLayoutInspector extends StatefulWidget {
  const NodeLayoutInspector({required this.editor, super.key});
  final SceneEditor editor;

  @override
  State<NodeLayoutInspector> createState() => _NodeLayoutInspectorState();
}

class _NodeLayoutInspectorState extends State<NodeLayoutInspector> {
  final _fields = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _updateFields();
  }

  @override
  void didUpdateWidget(NodeLayoutInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateFields();
  }

  void _updateFields() {
    final node = widget.editor.selectedNode;
    for (final entry in <String, String>{
      'Fixed width': node.sizing.width?.toString() ?? '',
      'Fixed height': node.sizing.height?.toString() ?? '',
      'Flex': '${node.sizing.flex}',
      'Padding': '${node.layout?.padding ?? 0}',
      'Gap': '${node.layout?.gap ?? 0}',
    }.entries) {
      _fields.putIfAbsent(entry.key, TextEditingController.new).text =
          entry.value;
    }
  }

  void _apply({
    SceneLayoutDirection? direction,
    SceneMainAlignment? main,
    SceneCrossAlignment? cross,
    bool? clip,
  }) {
    final editor = widget.editor;
    if (!editor.applyDraft()) return;
    final node = editor.selectedNode;
    final layout = node.layout;
    try {
      double number(String label) =>
          getFiniteNumberInput(label, _fields[label]!.text);
      double? dimension(String label) =>
          _fields[label]!.text.trim().isEmpty ? null : number(label);
      editor.updateNode(
        node.copyWith(
          sizing: SceneSizing(
            width: dimension('Fixed width'),
            height: dimension('Fixed height'),
            flex: number('Flex'),
          ),
          layout: layout == null
              ? null
              : SceneLayout(
                  direction: direction ?? layout.direction,
                  padding: number('Padding'),
                  gap: number('Gap'),
                  mainAlignment: main ?? layout.mainAlignment,
                  crossAlignment: cross ?? layout.crossAlignment,
                  clip: clip ?? layout.clip,
                ),
        ),
      );
    } on FormatException catch (error) {
      editor.inspector.showError(error.message);
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget _field(String label) => StudioFormField(
    label: label,
    controller: _fields[label]!,
    inputKey: ValueKey('layout-$label'),
    onSubmitted: _apply,
    onFocusLost: _apply,
  );

  @override
  Widget build(BuildContext context) {
    final layout = widget.editor.selectedNode.layout;
    return StudioFormSection(
      title: layout == null ? 'Responsive sizing' : 'Frame layout',
      children: [
        if (layout != null) ...[
          StudioEnumSelect(
            value: layout.direction,
            values: SceneLayoutDirection.values,
            onChanged: (value) => _apply(direction: value),
          ),
          const Gap(12),
          StudioFieldRow(left: _field('Padding'), right: _field('Gap')),
          const Text('Main axis').small().muted(),
          const Gap(6),
          StudioEnumSelect(
            value: layout.mainAlignment,
            values: SceneMainAlignment.values,
            onChanged: (value) => _apply(main: value),
          ),
          const Gap(12),
          const Text('Cross axis').small().muted(),
          const Gap(6),
          StudioEnumSelect(
            value: layout.crossAlignment,
            values: SceneCrossAlignment.values,
            onChanged: (value) => _apply(cross: value),
          ),
          const Gap(12),
          Row(
            children: [
              const Expanded(child: Text('Clip content')),
              Switch(
                value: layout.clip,
                onChanged: (value) => _apply(clip: value),
              ),
            ],
          ),
          const Gap(12),
        ],
        StudioFieldRow(
          left: _field('Fixed width'),
          right: _field('Fixed height'),
        ),
        _field('Flex'),
        const Text(
          'Blank dimensions use proportions. Fixed sizes use logical pixels.',
        ).small().muted(),
        const Gap(12),
      ],
    );
  }
}
