import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import 'editor_controller.dart';
import 'editor_strings.dart';

/// Lists nodes topmost first and hosts the add, duplicate, and delete actions.
class NodeListPanel extends StatelessWidget {
  const NodeListPanel({required this.controller, super.key});

  final SceneEditorController controller;

  @override
  Widget build(BuildContext context) {
    final document = controller.document;
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
              onPressed: controller.addNode,
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: strings.duplicateNode,
              onPressed: controller.duplicateSelected,
              icon: const Icon(Icons.copy),
            ),
            IconButton(
              tooltip: strings.deleteNode,
              onPressed: controller.deleteSelected,
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
                  selected: node.id == controller.selectedNodeId,
                  title: Text(node.id),
                  subtitle: Text(node.kind.name),
                  onTap: () => controller.select(node.id),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        _PredicateToggles(controller: controller),
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
