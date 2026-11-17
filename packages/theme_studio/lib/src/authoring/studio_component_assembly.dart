import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../ui/studio_form.dart';
import 'scene_editor.dart';
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gap = theme.density.baseGap * theme.scaling;
    final inset = theme.density.baseContainerPadding * theme.scaling * .75;
    return SingleChildScrollView(
      key: const ValueKey('component-assembly'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ComponentLibrarySection(
            inset: inset,
            gap: gap,
            readOnly: readOnly,
            onCreate: editor.createComponent,
          ),
          ListenableBuilder(
            listenable: editor,
            builder: (context, _) {
              final layout = editor.layout;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (layout != null && layout.presets.length > 1) ...[
                    const Divider(),
                    _LayoutPresetSection(
                      inset: inset,
                      gap: gap,
                      layout: layout,
                      document: editor.document,
                      readOnly: readOnly,
                      onChanged: editor.updateLayoutPreset,
                    ),
                  ],
                  if (editor.presetCatalog.properties.isNotEmpty) ...[
                    const Divider(),
                    _ThemePresetsSection(
                      inset: inset,
                      gap: gap,
                      editor: editor,
                      readOnly: readOnly,
                    ),
                  ],
                  if (layout != null) ...[
                    const Divider(),
                    _LayoutSlotsSection(
                      inset: inset,
                      gap: gap,
                      layout: layout,
                      editor: editor,
                      readOnly: readOnly,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ComponentLibrarySection extends StatelessWidget {
  const _ComponentLibrarySection({
    required this.inset,
    required this.gap,
    required this.readOnly,
    required this.onCreate,
  });

  final double inset;
  final double gap;
  final bool readOnly;
  final ValueChanged<StudioComponent> onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.all(inset),
      child: StudioFormSection(
        title: 'Component library',
        headerSpacing: gap,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: gap * .75,
              runSpacing: gap * .75,
              children: [
                for (final component in StudioComponent.values)
                  SizedBox(
                    width: (constraints.maxWidth - gap * .75) / 2,
                    child: Draggable<StudioComponent>(
                      data: component,
                      affinity: Axis.horizontal,
                      dragAnchorStrategy: pointerDragAnchorStrategy,
                      maxSimultaneousDrags: readOnly ? 0 : 1,
                      feedback: Container(
                        padding: EdgeInsets.all(inset),
                        color: theme.colorScheme.background,
                        child: Text(component.label),
                      ),
                      child: OutlineButton(
                        key: ValueKey('add-component-${component.name}'),
                        density: ButtonDensity.dense,
                        alignment: Alignment.centerLeft,
                        onPressed: readOnly ? null : () => onCreate(component),
                        child: Row(
                          children: [
                            Icon(
                              component.icon,
                              size: theme.typography.small.fontSize,
                            ),
                            Gap(gap * .75),
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
        ],
      ),
    );
  }
}

class _LayoutPresetSection extends StatelessWidget {
  const _LayoutPresetSection({
    required this.inset,
    required this.gap,
    required this.layout,
    required this.document,
    required this.readOnly,
    required this.onChanged,
  });

  final double inset;
  final double gap;
  final ThemeLayoutDefinition layout;
  final SceneDocument document;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(inset),
    child: StudioFormSection(
      title: layout.label,
      spacing: gap,
      children: [
        StudioLabeledField(
          label: 'Layout preset',
          child: StudioSelect<String>(
            key: const ValueKey('layout-preset'),
            enabled: !readOnly,
            value: layout.getPresetId(document),
            values: layout.presets.keys,
            formatValue: (id) => layout.presets[id]!.label,
            onChanged: onChanged,
          ),
        ),
      ],
    ),
  );
}

class _ThemePresetsSection extends StatelessWidget {
  const _ThemePresetsSection({
    required this.inset,
    required this.gap,
    required this.editor,
    required this.readOnly,
  });

  final double inset;
  final double gap;
  final SceneEditor editor;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(inset),
    child: StudioFormSection(
      title: 'Theme presets',
      spacing: gap,
      children: [
        for (final property in editor.presetCatalog.properties)
          StudioLabeledField(
            label: property.label,
            child: StudioEnumSelect<Enum>(
              enabled: !readOnly,
              key: ValueKey('preset-${property.name}'),
              value: property.getValue(editor.document.themeProperties),
              values: property.choices.keys,
              formatValue: (value) => property.choices[value]!,
              onChanged: (value) =>
                  editor.updateThemeProperty(property.name, value.name),
            ),
          ),
      ],
    ),
  );
}

class _LayoutSlotsSection extends StatelessWidget {
  const _LayoutSlotsSection({
    required this.inset,
    required this.gap,
    required this.layout,
    required this.editor,
    required this.readOnly,
  });

  final double inset;
  final double gap;
  final ThemeLayoutDefinition layout;
  final SceneEditor editor;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final ids = editor.document.nodes.map((node) => node.id).toSet();
    final slots = layout.getSlots(editor.document);
    final groups = [
      ('Optional components', slots.where((slot) => !slot.isRequired).toList()),
      ('Required controls', slots.where((slot) => slot.isRequired).toList()),
    ];
    return Padding(
      padding: EdgeInsets.all(inset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gap * 1.5,
        children: [
          if (layout.presets.length <= 1) Text(layout.label).small().semiBold(),
          for (final (label, group) in groups)
            if (group.isNotEmpty)
              StudioFormSection(
                title: label,
                headerSpacing: gap,
                spacing: gap * .25,
                children: [
                  for (final slot in group)
                    _AssemblySlot(
                      editor: editor,
                      slot: slot,
                      isPresent: ids.contains(slot.defaultNode.id),
                      readOnly: readOnly,
                    ),
                ],
              ),
          const Text(
            'Use Login / Dormant to preview both states. '
            'Turning a component back on restores its defaults; '
            'Undo restores your edits.',
          ).xSmall().muted(),
        ],
      ),
    );
  }
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final gap = theme.density.baseGap * theme.scaling;
    final canToggle =
        !readOnly &&
        (!isPresent ||
            editor.getDeletionBlockReason(slot.defaultNode.id) == null);
    final row = AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : kDefaultDuration,
      curve: Curves.easeOut,
      padding: EdgeInsets.only(right: gap),
      decoration: BoxDecoration(
        color: selected
            ? colors.secondary
            : colors.secondary.withValues(alpha: 0),
        borderRadius: theme.borderRadiusMd,
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
          Gap(gap * .75),
          if (slot.isRequired)
            if (isPresent)
              Semantics(
                label: '${slot.label}: required, included',
                child: Icon(
                  LucideIcons.lockKeyhole,
                  key: ValueKey('slot-${slot.defaultNode.id}'),
                  size: theme.typography.small.fontSize,
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
                child: const Text('Add').xSmall(),
              )
          else
            Semantics(
              label: 'Include ${slot.label}',
              child: Checkbox(
                key: ValueKey('slot-${slot.defaultNode.id}'),
                state: isPresent
                    ? CheckboxState.checked
                    : CheckboxState.unchecked,
                enabled: canToggle,
                onChanged: canToggle
                    ? (value) => editor.updateLayoutSlot(
                        slot.defaultNode.id,
                        isPresent: value == CheckboxState.checked,
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
    if (readOnly) return row;
    return Draggable<SceneNode>(
      data: slot.defaultNode,
      affinity: Axis.horizontal,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        padding: EdgeInsets.all(
          theme.density.baseContainerPadding * theme.scaling * .75,
        ),
        decoration: BoxDecoration(
          color: colors.background,
          border: Border.all(color: colors.primary),
          borderRadius: theme.borderRadiusMd,
        ),
        child: Text(
          slot.label,
          style: theme.typography.small.copyWith(color: colors.foreground),
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
      return Column(
        key: const ValueKey('layout-completeness'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                Text(
                  'Missing required components: ${missing.map((slot) => slot.label).join(', ')}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ).xSmall(),
                OutlineButton(
                  key: const ValueKey('add-required-slots'),
                  density: ButtonDensity.dense,
                  onPressed: readOnly ? null : editor.addRequiredLayoutSlots,
                  child: const Text('Add required').small(),
                ),
              ],
            ),
          ),
          const Divider(),
        ],
      );
    },
  );
}
