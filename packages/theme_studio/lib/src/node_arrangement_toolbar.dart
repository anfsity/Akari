import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'node_geometry.dart';
import 'scene_editor.dart';

class NodeArrangementToolbar extends StatelessWidget {
  const NodeArrangementToolbar({required this.editor, super.key});
  final SceneEditor editor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text('${editor.selectedIds.length} selected').small().muted(),
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
        OutlineButton(
          key: const ValueKey('stagger-selection'),
          density: ButtonDensity.dense,
          onPressed: editor.selectedIds.length > 1
              ? () => editor.staggerSelection(100)
              : null,
          child: const Text('Stagger 100 ms'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(height: 18, child: VerticalDivider()),
        ),
        for (final alignment in NodeAlignment.values)
          Tooltip(
            tooltip: (_) => Text(_getAlignmentLabel(alignment)),
            child: OutlineButton(
              key: ValueKey('align-${alignment.name}'),
              density: ButtonDensity.iconDense,
              onPressed: editor.canArrange
                  ? () => editor.alignSelection(alignment)
                  : null,
              child: Semantics(
                label: _getAlignmentLabel(alignment),
                child: Icon(
                  switch (alignment) {
                    NodeAlignment.left => LucideIcons.alignStartVertical,
                    NodeAlignment.center => LucideIcons.alignCenterVertical,
                    NodeAlignment.right => LucideIcons.alignEndVertical,
                    NodeAlignment.top => LucideIcons.alignStartHorizontal,
                    NodeAlignment.middle => LucideIcons.alignCenterHorizontal,
                    NodeAlignment.bottom => LucideIcons.alignEndHorizontal,
                  },
                  size: 15,
                ),
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(height: 18, child: VerticalDivider()),
        ),
        for (final horizontal in [true, false])
          Tooltip(
            tooltip: (_) => Text(
              horizontal ? 'Distribute horizontally' : 'Distribute vertically',
            ),
            child: OutlineButton(
              key: ValueKey(
                'distribute-${horizontal ? 'horizontal' : 'vertical'}',
              ),
              density: ButtonDensity.iconDense,
              onPressed: editor.canArrange && editor.selectedIds.length >= 3
                  ? () => editor.distributeSelection(horizontal: horizontal)
                  : null,
              child: Semantics(
                label: horizontal
                    ? 'Distribute horizontally'
                    : 'Distribute vertically',
                child: Icon(
                  horizontal
                      ? LucideIcons.alignHorizontalSpaceBetween
                      : LucideIcons.alignVerticalSpaceBetween,
                  size: 15,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  static String _getAlignmentLabel(NodeAlignment alignment) =>
      switch (alignment) {
        NodeAlignment.left => 'Align left',
        NodeAlignment.center => 'Align horizontal center',
        NodeAlignment.right => 'Align right',
        NodeAlignment.top => 'Align top',
        NodeAlignment.middle => 'Align vertical center',
        NodeAlignment.bottom => 'Align bottom',
      };
}
