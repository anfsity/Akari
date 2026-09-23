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
  double _predicatesHeight = 240;

  static const _minPredicatesHeight = 72.0;
  static const _maxPredicatesHeight = 420.0;

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
          child: ListView.builder(
            itemCount: nodes.length,
            itemBuilder: (context, index) {
              final node = nodes[index];
              return _NodeTile(controller: widget.controller, node: node);
            },
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

class _NodeTile extends StatefulWidget {
  const _NodeTile({required this.controller, required this.node});

  final SceneEditorController controller;
  final SceneNode node;

  @override
  State<_NodeTile> createState() => _NodeTileState();
}

class _NodeTileState extends State<_NodeTile> {
  late bool _selected;

  @override
  void initState() {
    super.initState();
    _selected = _isSelected;
    widget.controller.selectionListenable.addListener(_handleSelectionChanged);
  }

  @override
  void didUpdateWidget(_NodeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.selectionListenable.removeListener(
        _handleSelectionChanged,
      );
      widget.controller.selectionListenable.addListener(
        _handleSelectionChanged,
      );
    }
    final selected = _isSelected;
    if (selected != _selected) {
      _selected = selected;
    }
  }

  @override
  void dispose() {
    widget.controller.selectionListenable.removeListener(
      _handleSelectionChanged,
    );
    super.dispose();
  }

  bool get _isSelected => widget.node.id == widget.controller.selectedNodeId;

  void _handleSelectionChanged() {
    final selected = _isSelected;
    if (selected == _selected) {
      return;
    }
    setState(() => _selected = selected);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: _selected,
      title: Text(widget.node.id),
      subtitle: Text(widget.node.kind.name),
      onTap: () => widget.controller.select(widget.node.id),
    );
  }
}

class _PredicateToggles extends StatelessWidget {
  const _PredicateToggles({required this.controller});

  final SceneEditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.predicatesListenable,
      builder: (context, _) {
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
                      label: Text(strings.predicateLabel(predicate)),
                      selected: controller.activePredicates.contains(predicate),
                      onSelected: (_) => controller.togglePredicate(predicate),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
