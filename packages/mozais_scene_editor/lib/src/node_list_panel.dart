import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import 'editor_controller.dart';
import 'editor_strings.dart';
import 'pane_divider.dart';

/// Lists nodes topmost first and hosts the add, duplicate, and delete actions.
///
/// The active-predicate toggles sit below a draggable divider so the two
/// sections can be resized vertically.
class NodeListPanel extends StatefulWidget {
  const NodeListPanel({required this.controller, super.key});

  final SceneEditorController controller;

  @override
  State<NodeListPanel> createState() => _NodeListPanelState();
}

class _NodeListPanelState extends State<NodeListPanel> {
  double _predicatesHeight = 180;

  static const _minPredicatesHeight = 72.0;
  static const _maxPredicatesHeight = 360.0;

  void _resizePredicates(double delta) {
    setState(() {
      _predicatesHeight = (_predicatesHeight - delta).clamp(
        _minPredicatesHeight,
        _maxPredicatesHeight,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.controller.document;
    if (document == null) {
      return const SizedBox.shrink();
    }
    final nodes = document.paintOrder.reversed.toList();
    final strings = EditorStringsScope.of(context);
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: strings.addNode,
              onPressed: widget.controller.addNode,
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: strings.duplicateNode,
              onPressed: widget.controller.duplicateSelected,
              icon: const Icon(Icons.copy),
            ),
            IconButton(
              tooltip: strings.deleteNode,
              onPressed: widget.controller.deleteSelected,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: [
              for (final node in nodes)
                ListTile(
                  dense: true,
                  selected: node.id == widget.controller.selectedNodeId,
                  title: Text(node.id),
                  subtitle: Text(node.kind.name),
                  onTap: () => widget.controller.select(node.id),
                ),
            ],
          ),
        ),
        PaneDivider(dragAxis: Axis.vertical, onDrag: _resizePredicates),
        SizedBox(
          key: const ValueKey('activePredicatesPane'),
          height: _predicatesHeight,
          child: SingleChildScrollView(
            child: _PredicateToggles(controller: widget.controller),
          ),
        ),
      ],
    );
  }
}

class _PredicateToggles extends StatelessWidget {
  const _PredicateToggles({required this.controller});

  final SceneEditorController controller;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.activePredicates,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final predicate in ScenePredicate.values)
                FilterChip(
                  label: Text(predicate.name),
                  selected: controller.activePredicates.contains(predicate),
                  onSelected: (_) => controller.togglePredicate(predicate),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
