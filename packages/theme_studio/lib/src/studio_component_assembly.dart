import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';

class StudioComponentAssembly extends StatelessWidget {
  const StudioComponentAssembly({
    required this.editor,
    required this.readOnly,
    super.key,
  });

  final SceneEditor editor;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editor,
    builder: (context, _) {
      final layout = editor.layout;
      if (layout == null) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Component assembly is unavailable for this scene.'),
        );
      }
      final ids = editor.document.nodes.map((node) => node.id).toSet();
      return ListView(
        key: const ValueKey('component-assembly'),
        padding: const EdgeInsets.all(12),
        children: [
          Text(layout.label).semiBold(),
          const Gap(8),
          const Text(
            'Add restores preset defaults. Undo restores removed edits.',
          ).small().muted(),
          const Gap(16),
          for (final slot in layout.slots)
            _AssemblySlot(
              editor: editor,
              slot: slot,
              isPresent: ids.contains(slot.defaultNode.id),
              readOnly: readOnly,
            ),
        ],
      );
    },
  );
}

class _AssemblySlot extends StatelessWidget {
  const _AssemblySlot({
    required this.editor,
    required this.slot,
    required this.isPresent,
    required this.readOnly,
  });

  final SceneEditor editor;
  final ThemeLayoutSlot slot;
  final bool isPresent;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: GhostButton(
            density: ButtonDensity.compact,
            onPressed: isPresent
                ? () => editor.selectNode(slot.defaultNode.id)
                : null,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slot.label, maxLines: 2).small(),
                  if (slot.isRequired) const Text('Required').small().muted(),
                ],
              ),
            ),
          ),
        ),
        const Gap(8),
        OutlineButton(
          key: ValueKey('slot-${slot.defaultNode.id}'),
          density: ButtonDensity.compact,
          onPressed:
              readOnly ||
                  (isPresent &&
                      editor.getDeletionBlockReason(slot.defaultNode.id) !=
                          null)
              ? null
              : () => editor.updateLayoutSlot(
                  slot.defaultNode.id,
                  isPresent: !isPresent,
                ),
          child: Text(isPresent ? 'Remove' : 'Add').small(),
        ),
      ],
    ),
  );
}

/// Remains visible above every sidebar tab so imported incomplete scenes can
/// be repaired without first knowing where the assembly panel lives.
class StudioLayoutCompleteness extends StatelessWidget {
  const StudioLayoutCompleteness({
    required this.editor,
    required this.readOnly,
    super.key,
  });

  final SceneEditor editor;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editor,
    builder: (context, _) {
      final missing = editor.missingRequiredSlots;
      if (missing.isEmpty) return const SizedBox();
      return Padding(
        key: const ValueKey('layout-completeness'),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Missing required components: ${missing.map((slot) => slot.label).join(', ')}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ).small(),
            const Gap(8),
            OutlineButton(
              key: const ValueKey('add-required-slots'),
              onPressed: readOnly ? null : editor.addRequiredLayoutSlots,
              child: const Text('Add required').small(),
            ),
          ],
        ),
      );
    },
  );
}
