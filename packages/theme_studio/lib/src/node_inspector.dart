import 'dart:convert';

import 'package:scene/scene.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class NodeInspector extends StatefulWidget {
  const NodeInspector({
    required this.node,
    required this.onUpdate,
    required this.onDraftChanged,
    super.key,
  });

  final SceneNode node;
  final ValueChanged<SceneNode> onUpdate;
  final ValueChanged<bool> onDraftChanged;

  @override
  State<NodeInspector> createState() => NodeInspectorState();
}

class NodeInspectorState extends State<NodeInspector> {
  final _fields = <String, TextEditingController>{};
  late SceneMotionPreset _motion;
  String? _error;
  bool _updatingFields = false;

  @override
  void initState() {
    super.initState();
    _updateFields();
  }

  @override
  void didUpdateWidget(NodeInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.node, widget.node)) _updateFields();
  }

  void _updateFields() {
    _updatingFields = true;
    final node = widget.node;
    final transform = node.transform;
    final values = <String, Object>{
      'X': node.rect.x,
      'Y': node.rect.y,
      'Width': node.rect.width,
      'Height': node.rect.height,
      'Depth': node.z,
      'Paint order': node.renderOrder,
      'Focus order': node.focusOrder,
      'Translate X': transform.translateX,
      'Translate Y': transform.translateY,
      'Scale X': transform.scaleX,
      'Scale Y': transform.scaleY,
      'Rotate X': transform.rotationX,
      'Rotate Y': transform.rotationY,
      'Rotate Z': transform.rotationZ,
      'Pivot X': transform.pivotX,
      'Pivot Y': transform.pivotY,
      'Perspective': transform.perspective,
      'Properties': const JsonEncoder.withIndent('  ').convert(node.properties),
    };
    for (final entry in values.entries) {
      (_fields[entry.key] ??= TextEditingController()).text = '${entry.value}';
    }
    _motion = node.motion;
    _error = null;
    _updatingFields = false;
  }

  double _getNumber(String label) {
    final value = double.tryParse(_fields[label]!.text);
    if (value == null || !value.isFinite) {
      throw FormatException('$label must be a finite number.');
    }
    return value;
  }

  int _getInteger(String label) {
    final value = int.tryParse(_fields[label]!.text);
    if (value == null) throw FormatException('$label must be an integer.');
    return value;
  }

  bool apply() {
    try {
      final properties = jsonDecode(_fields['Properties']!.text);
      if (properties is! Map<String, dynamic> ||
          properties.values.any((value) => value is! String || value.isEmpty)) {
        throw const FormatException(
          'Properties must be an object of non-empty strings.',
        );
      }
      widget.onUpdate(
        widget.node.copyWith(
          rect: SceneRect(
            x: _getNumber('X'),
            y: _getNumber('Y'),
            width: _getNumber('Width'),
            height: _getNumber('Height'),
          ),
          z: _getInteger('Depth'),
          renderOrder: _getInteger('Paint order'),
          focusOrder: _getInteger('Focus order'),
          motion: _motion,
          transform: SceneTransform(
            translateX: _getNumber('Translate X'),
            translateY: _getNumber('Translate Y'),
            scaleX: _getNumber('Scale X'),
            scaleY: _getNumber('Scale Y'),
            rotationX: _getNumber('Rotate X'),
            rotationY: _getNumber('Rotate Y'),
            rotationZ: _getNumber('Rotate Z'),
            pivotX: _getNumber('Pivot X'),
            pivotY: _getNumber('Pivot Y'),
            perspective: _getNumber('Perspective'),
          ),
          properties: properties.cast<String, String>(),
        ),
      );
      setState(() => _error = null);
      widget.onDraftChanged(false);
      return true;
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return false;
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.node.id).semiBold(),
              Text(widget.node.componentId).muted().small(),
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
                value: _motion,
                onChanged: (value) {
                  setState(() => _motion = value!);
                  widget.onDraftChanged(true);
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
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.destructive,
                  ),
                ).small(),
                const Gap(12),
              ],
              PrimaryButton(
                onPressed: apply,
                child: const Text('Apply to preview'),
              ),
            ],
          ),
        ),
      ],
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
            controller: _fields[label],
            maxLines: maxLines,
            // shadcn also emits onChanged for controller writes during refresh.
            onChanged: (_) {
              if (!_updatingFields) widget.onDraftChanged(true);
            },
            onSubmitted: maxLines == 1 ? (_) => apply() : null,
          ),
        ),
      ],
    ),
  );
}
