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
            'Choose components, then select one to customize. '
            'The layout supplies its starting position.',
          ).small().muted(),
          const Gap(16),
          for (final (label, slots) in [
            (
              'Optional components',
              layout.slots.where((slot) => !slot.isRequired).toList(),
            ),
            (
              'Required controls',
              layout.slots.where((slot) => slot.isRequired).toList(),
            ),
          ])
            if (slots.isNotEmpty) ...[
              Text(label).small().semiBold(),
              const Gap(8),
              for (final slot in slots)
                _AssemblySlot(
                  editor: editor,
                  slot: slot,
                  isPresent: ids.contains(slot.defaultNode.id),
                  readOnly: readOnly,
                ),
              const Gap(12),
            ],
          const Text(
            'Use Login / Dormant to preview both states. '
            'Turning a component back on restores its defaults; '
            'Undo restores your edits.',
          ).small().muted(),
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
  Widget build(BuildContext context) {
    final selected = isPresent && editor.selectedId == slot.defaultNode.id;
    final colors = Theme.of(context).colorScheme;
    final canToggle =
        !readOnly &&
        (!isPresent ||
            editor.getDeletionBlockReason(slot.defaultNode.id) == null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? colors.secondary : null,
          border: Border.all(color: selected ? colors.primary : colors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: GhostButton(
                key: ValueKey('select-slot-${slot.defaultNode.id}'),
                density: ButtonDensity.dense,
                alignment: Alignment.centerLeft,
                onPressed: isPresent
                    ? () => editor.selectNode(slot.defaultNode.id)
                    : null,
                child: Text(
                  slot.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ).small(),
              ),
            ),
            const Gap(8),
            if (slot.isRequired)
              if (isPresent)
                Semantics(
                  label: '${slot.label}: required, included',
                  child: Icon(
                    LucideIcons.check,
                    key: ValueKey('slot-${slot.defaultNode.id}'),
                    size: 16,
                    color: colors.mutedForeground,
                  ),
                )
              else
                OutlineButton(
                  key: ValueKey('slot-${slot.defaultNode.id}'),
                  density: ButtonDensity.dense,
                  onPressed: readOnly
                      ? null
                      : () => editor.updateLayoutSlot(
                          slot.defaultNode.id,
                          isPresent: true,
                        ),
                  child: const Text('Add').small(),
                )
            else
              Semantics(
                label: 'Include ${slot.label}',
                child: Switch(
                  key: ValueKey('slot-${slot.defaultNode.id}'),
                  value: isPresent,
                  enabled: canToggle,
                  onChanged: canToggle
                      ? (value) => editor.updateLayoutSlot(
                          slot.defaultNode.id,
                          isPresent: value,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
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
