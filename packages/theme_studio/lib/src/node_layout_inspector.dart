import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_form.dart';
import 'studio_form_values.dart';

class NodeLayoutInspector extends StatefulWidget {
  const NodeLayoutInspector({required this.editor, super.key});
  final SceneEditor editor;
  @override
  State<NodeLayoutInspector> createState() => _NodeLayoutInspectorState();
}

class _NodeLayoutInspectorState extends State<NodeLayoutInspector> {
  final _fields = <String, TextEditingController>{};
  int _editing = -1;
  String? _nodeId;
  SceneBreakpoint? get _rule =>
      _editing < 0 ? null : widget.editor.selectedNode.breakpoints[_editing];
  SceneSizing get _sizing => _rule?.sizing ?? widget.editor.selectedNode.sizing;
  SceneLayout? get _layout =>
      _rule?.layout ?? widget.editor.selectedNode.layout;
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
    if (_nodeId != node.id || _editing >= node.breakpoints.length) {
      _editing = -1;
    }
    _nodeId = node.id;
    final sizing = _sizing;
    for (final entry in <String, String>{
      'Fixed width': sizing.width?.toString() ?? '',
      'Fixed height': sizing.height?.toString() ?? '',
      'Min width': '${sizing.minWidth}',
      'Min height': '${sizing.minHeight}',
      'Max width': sizing.maxWidth?.toString() ?? '',
      'Max height': sizing.maxHeight?.toString() ?? '',
      'Flex': '${sizing.flex}',
      'Padding': '${_layout?.padding ?? 0}',
      'Gap': '${_layout?.gap ?? 0}',
      'Viewport ≥ px': '${_rule?.minWidth ?? 640}',
    }.entries) {
      _fields.putIfAbsent(entry.key, TextEditingController.new).text =
          entry.value;
    }
  }

  void _apply({
    SceneLayoutDirection? direction,
    SceneMainAlignment? main,
    SceneCrossAlignment? cross,
    SceneSizeMode? widthMode,
    SceneSizeMode? heightMode,
    bool? clip,
    bool? wrap,
  }) {
    final editor = widget.editor;
    if (!editor.applyDraft()) return;
    final node = editor.selectedNode;
    final layout = _layout;
    try {
      double number(String label) =>
          getFiniteNumberInput(label, _fields[label]!.text);
      double? dimension(String label) =>
          _fields[label]!.text.trim().isEmpty ? null : number(label);
      final sizing = SceneSizing(
        width: widthMode == null ? dimension('Fixed width') : null,
        height: heightMode == null ? dimension('Fixed height') : null,
        widthMode: widthMode ?? _sizing.widthMode,
        heightMode: heightMode ?? _sizing.heightMode,
        flex: number('Flex'),
        minWidth: number('Min width'),
        minHeight: number('Min height'),
        maxWidth: dimension('Max width'),
        maxHeight: dimension('Max height'),
      );
      final updatedLayout = layout == null
          ? null
          : SceneLayout(
              direction: direction ?? layout.direction,
              padding: number('Padding'),
              gap: number('Gap'),
              mainAlignment: main ?? layout.mainAlignment,
              crossAlignment: cross ?? layout.crossAlignment,
              clip: clip ?? layout.clip,
              wrap: wrap ?? layout.wrap,
            );
      editor.updateNode(
        _editing < 0
            ? node.copyWith(sizing: sizing, layout: updatedLayout)
            : node.copyWith(
                breakpoints: [...node.breakpoints]
                  ..[_editing] = SceneBreakpoint(
                    minWidth: number('Viewport ≥ px'),
                    sizing: sizing,
                    layout: updatedLayout,
                  ),
              ),
      );
    } on FormatException catch (error) {
      editor.inspector.showError(error.message);
    }
  }

  void _addBreakpoint() {
    final editor = widget.editor;
    if (!editor.applyDraft()) return;
    final node = editor.selectedNode;
    var width = 640.0;
    while (node.breakpoints.any((rule) => rule.minWidth == width)) {
      width += 320;
    }
    editor.updateNode(
      node.copyWith(
        breakpoints: [
          ...node.breakpoints,
          SceneBreakpoint(
            minWidth: width,
            layout: node.layout,
            sizing: node.sizing,
          ),
        ],
      ),
    );
    setState(() {
      _editing = node.breakpoints.length;
      _updateFields();
    });
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
    final node = widget.editor.selectedNode;
    final layout = _layout;
    final modes = SceneSizeMode.values
        .where(
          (mode) =>
              mode != SceneSizeMode.hug ||
              node.layout != null ||
              node.primitive == ScenePrimitive.text,
        )
        .toList();
    return StudioFormSection(
      title: layout == null ? 'Responsive sizing' : 'Frame layout',
      children: [
        StudioSelect<int>(
          value: _editing,
          values: [-1, for (var i = 0; i < node.breakpoints.length; i++) i],
          formatValue: (index) => index < 0
              ? 'Base layout'
              : 'Viewport ≥ ${node.breakpoints[index].minWidth.round()} px',
          onChanged: (value) => setState(() {
            _editing = value;
            _updateFields();
          }),
        ),
        const Gap(8),
        if (_editing >= 0) _field('Viewport ≥ px'),
        Wrap(
          spacing: 8,
          children: [
            OutlineButton(
              key: const ValueKey('layout-add-breakpoint'),
              onPressed: _addBreakpoint,
              child: const Text('Add breakpoint'),
            ),
            if (_editing >= 0)
              GhostButton(
                onPressed: () {
                  final rules = [...node.breakpoints]..removeAt(_editing);
                  setState(() {
                    _editing = -1;
                  });
                  widget.editor.updateNode(node.copyWith(breakpoints: rules));
                },
                child: const Text('Remove'),
              ),
          ],
        ),
        const Gap(12),
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
              const Expanded(child: Text('Wrap children')),
              Switch(
                value: layout.wrap,
                onChanged: (value) => _apply(wrap: value),
              ),
            ],
          ),
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
        const Text('Width / Height').small().muted(),
        const Gap(6),
        StudioFieldRow(
          left: StudioEnumSelect(
            value: _sizing.widthMode,
            values: modes,
            onChanged: (value) => _apply(widthMode: value),
          ),
          right: StudioEnumSelect(
            value: _sizing.heightMode,
            values: modes,
            onChanged: (value) => _apply(heightMode: value),
          ),
        ),
        const Gap(8),
        StudioFieldRow(
          left: _field('Fixed width'),
          right: _field('Fixed height'),
        ),
        StudioFieldRow(left: _field('Min width'), right: _field('Min height')),
        StudioFieldRow(left: _field('Max width'), right: _field('Max height')),
        _field('Flex'),
        const Text(
          'Blank fixed sizes use the selected mode. Hug measures text or frame contents; fill shares the available space. Breakpoints use logical viewport width.',
        ).small().muted(),
        const Gap(12),
      ],
    );
  }
}
