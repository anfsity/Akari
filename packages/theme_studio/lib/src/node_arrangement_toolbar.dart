import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'node_geometry.dart';
import 'scene_editor.dart';

class NodeArrangementToolbar extends StatelessWidget {
  const NodeArrangementToolbar({required this.editor, super.key});
  final SceneEditor editor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${editor.selectedIds.length} selected').small().muted(),
        OutlineButton(
          key: const ValueKey('stagger-selection'),
          density: ButtonDensity.dense,
          onPressed: editor.selectedIds.length > 1
              ? () => editor.staggerSelection(100)
              : null,
          child: const Text('Stagger 100 ms'),
        ),
        OutlineButton(
          key: const ValueKey('group-selection'),
          density: ButtonDensity.dense,
          onPressed: editor.canGroup ? editor.groupSelection : null,
          child: const Text('Group'),
        ),
        if (editor.selectedNode.layout != null)
          OutlineButton(
            key: const ValueKey('ungroup-selection'),
            density: ButtonDensity.dense,
            onPressed: editor.canUngroup ? editor.ungroupSelection : null,
            child: const Text('Ungroup'),
          ),
        for (final alignment in NodeAlignment.values)
          OutlineButton(
            key: ValueKey('align-${alignment.name}'),
            density: ButtonDensity.dense,
            onPressed: editor.canArrange
                ? () => editor.alignSelection(alignment)
                : null,
            child: Text(switch (alignment) {
              NodeAlignment.left => 'Left',
              NodeAlignment.center => 'H center',
              NodeAlignment.right => 'Right',
              NodeAlignment.top => 'Top',
              NodeAlignment.middle => 'V center',
              NodeAlignment.bottom => 'Bottom',
            }),
          ),
        for (final horizontal in [true, false])
          OutlineButton(
            key: ValueKey(
              'distribute-${horizontal ? 'horizontal' : 'vertical'}',
            ),
            density: ButtonDensity.dense,
            onPressed: editor.canArrange && editor.selectedIds.length >= 3
                ? () => editor.distributeSelection(horizontal: horizontal)
                : null,
            child: Text(horizontal ? 'Space horizontally' : 'Space vertically'),
          ),
      ],
    ),
  );
}
