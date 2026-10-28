import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_form.dart';
import 'studio_components.dart';

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
      final ids = editor.document.nodes.map((node) => node.id).toSet();
      final slots =
          layout?.getSlots(editor.document) ?? const <ThemeLayoutSlot>[];
      return SingleChildScrollView(
        key: const ValueKey('component-assembly'),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Component library').small().semiBold(),
            const Gap(8),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final component in StudioComponent.values)
                    SizedBox(
                      width: (constraints.maxWidth - 6) / 2,
                      height: 32,
                      child: Draggable<StudioComponent>(
                        data: component,
                        affinity: Axis.horizontal,
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        maxSimultaneousDrags: readOnly ? 0 : 1,
                        feedback: Container(
                          padding: const EdgeInsets.all(12),
                          color: Theme.of(context).colorScheme.background,
                          child: Text(component.label),
                        ),
                        child: OutlineButton(
                          key: ValueKey('add-component-${component.name}'),
                          density: ButtonDensity.dense,
                          alignment: Alignment.centerLeft,
                          onPressed: readOnly
                              ? null
                              : () => editor.createComponent(component),
                          child: Row(
                            children: [
                              Icon(component.icon, size: 14),
                              const Gap(4),
                              Expanded(
                                child: Text(
                                  component.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ).xSmall(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Gap(16),
            const Divider(),
            const Gap(16),
            Text(layout?.label ?? 'Theme customization').small().semiBold(),
            const Gap(8),
            if (layout != null && layout.presets.length > 1) ...[
              const Text('Layout preset').small().muted(),
              const Gap(6),
              StudioSelect<String>(
                key: const ValueKey('layout-preset'),
                enabled: !readOnly,
                value: layout.getPresetId(editor.document),
                values: layout.presets.keys,
                formatValue: (id) => layout.presets[id]!.label,
                onChanged: editor.updateLayoutPreset,
              ),
              const Gap(12),
            ],
            if (editor.presetCatalog.properties.isNotEmpty) ...[
              const Text('Theme presets').small().semiBold(),
              const Gap(8),
              for (final property in editor.presetCatalog.properties)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(property.label).small().muted(),
                      const Gap(6),
                      StudioEnumSelect<Enum>(
                        enabled: !readOnly,
                        key: ValueKey('preset-${property.name}'),
                        value: property.getValue(
                          editor.document.themeProperties,
                        ),
                        values: property.choices.keys,
                        formatValue: (value) => property.choices[value]!,
                        onChanged: (value) => editor.updateThemeProperty(
                          property.name,
                          value.name,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (layout != null) ...[
              const Divider(),
              const Gap(16),
              for (final (label, slots) in [
                (
                  'Optional components',
                  slots.where((slot) => !slot.isRequired).toList(),
                ),
                (
                  'Required controls',
                  slots.where((slot) => slot.isRequired).toList(),
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
            ],
            if (layout != null)
              const Text(
                'Use Login / Dormant to preview both states. '
                'Turning a component back on restores its defaults; '
                'Undo restores your edits.',
              ).small().muted(),
          ],
        ),
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
    final row = Padding(
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
    if (readOnly) return row;
    return Draggable<SceneNode>(
      data: slot.defaultNode,
      affinity: Axis.horizontal,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.background,
          border: Border.all(color: colors.primary),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          slot.label,
          style: TextStyle(color: colors.foreground, fontSize: 14),
        ),
      ),
      childWhenDragging: Opacity(opacity: .4, child: row),
      child: row,
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
