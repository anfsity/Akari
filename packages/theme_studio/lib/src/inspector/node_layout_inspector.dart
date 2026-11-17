import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../ui/studio_form.dart';
import '../ui/studio_tooltip.dart';

class NodeLayoutInspector extends StatelessWidget {
  const NodeLayoutInspector({required this.editor, super.key});

  final SceneEditor editor;

  static const _prefixes = <String, String>{
    'Fixed width': 'Fix W',
    'Fixed height': 'Fix H',
    'Min width': 'Min W',
    'Min height': 'Min H',
    'Max width': 'Max W',
    'Max height': 'Max H',
    'Flex': 'Flex',
    'Padding': 'Pad',
    'Gap': 'Gap',
    'Viewport ≥ px': '≥ px',
  };

  void _applyOptions({
    SceneLayoutDirection? direction,
    SceneMainAlignment? main,
    SceneCrossAlignment? cross,
    SceneSizeMode? widthMode,
    SceneSizeMode? heightMode,
    bool? clip,
    bool? wrap,
  }) {
    editor.inspector.updateLayoutOptions(
      direction: direction,
      mainAlignment: main,
      crossAlignment: cross,
      widthMode: widthMode,
      heightMode: heightMode,
      clip: clip,
      wrap: wrap,
    );
    editor.tryApplyDraft();
  }

  void _addBreakpoint() {
    if (!editor.tryApplyDraft()) return;
    final node = editor.selectedNode;
    final nextIndex = node.breakpoints.length;
    var width = 640.0;
    while (node.breakpoints.any((rule) => rule.minWidth == width)) {
      width += 320;
    }
    editor.updateNode(
      node.copyWith(
        breakpoints: [
          ...node.breakpoints,
          SceneBreakpoint(
            minWidth: width,
            layout: node.layout,
            sizing: node.sizing,
          ),
        ],
      ),
    );
    editor.inspector.selectEditingBreakpoint(nextIndex);
  }

  void _removeBreakpoint() {
    final index = editor.inspector.editingBreakpoint;
    if (index < 0 || !editor.tryApplyDraft()) return;
    final current = editor.selectedNode;
    final rules = [...current.breakpoints]..removeAt(index);
    editor.updateNode(current.copyWith(breakpoints: rules));
    editor.inspector.selectEditingBreakpoint(-1);
  }

  Widget _field(String label) => StudioFormField(
    label: label,
    prefix: _prefixes[label],
    controller: editor.inspector.getField(label),
    inputKey: ValueKey('layout-$label'),
    onSubmitted: editor.tryApplyDraft,
    onFocusLost: editor.tryApplyDraft,
  );

  @override
  Widget build(BuildContext context) {
    final controller = editor.inspector;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final node = controller.node;
        final editing = controller.editingBreakpoint;
        final sizing = controller.sizing;
        final layout = controller.layout;
        final modes = SceneSizeMode.values
            .where(
              (mode) =>
                  mode != SceneSizeMode.hug ||
                  node.layout != null ||
                  node.primitive == ScenePrimitive.text,
            )
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: StudioFormSection(
                title: layout == null ? 'Responsive sizing' : 'Frame layout',
                spacing: 10,
                children: [
                  Row(
                    spacing: 6,
                    children: [
                      Expanded(
                        child: StudioSelect<int>(
                          value: editing,
                          values: [
                            -1,
                            for (var i = 0; i < node.breakpoints.length; i++) i,
                          ],
                          formatValue: (index) => index < 0
                              ? 'Base layout'
                              : 'Viewport ≥ ${node.breakpoints[index].minWidth.round()} px',
                          onChanged: (value) {
                            if (controller.hasDraft) editor.tryApplyDraft();
                            controller.selectEditingBreakpoint(value);
                          },
                        ),
                      ),
                      StudioTooltip(
                        tooltip: (_) => const Text('Add breakpoint'),
                        child: Semantics(
                          label: 'Add breakpoint',
                          child: OutlineButton(
                            key: const ValueKey('layout-add-breakpoint'),
                            density: ButtonDensity.icon,
                            onPressed: _addBreakpoint,
                            child: const Icon(LucideIcons.plus, size: 16),
                          ),
                        ),
                      ),
                      if (editing >= 0)
                        StudioTooltip(
                          tooltip: (_) => const Text('Remove breakpoint'),
                          child: Semantics(
                            label: 'Remove breakpoint',
                            child: GhostButton(
                              key: const ValueKey('layout-remove-breakpoint'),
                              density: ButtonDensity.icon,
                              onPressed: _removeBreakpoint,
                              child: const Icon(LucideIcons.minus, size: 16),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (editing >= 0) _field('Viewport ≥ px'),
                  if (layout != null) ...[
                    StudioLabeledField(
                      label: 'Direction',
                      child: StudioEnumSelect(
                        value: layout.direction,
                        values: SceneLayoutDirection.values,
                        onChanged: (value) => _applyOptions(direction: value),
                      ),
                    ),
                    StudioFieldRow(
                      left: _field('Padding'),
                      right: _field('Gap'),
                    ),
                    StudioLabeledField(
                      label: 'Main axis',
                      child: StudioEnumSelect(
                        value: layout.mainAlignment,
                        values: SceneMainAlignment.values,
                        onChanged: (value) => _applyOptions(main: value),
                      ),
                    ),
                    StudioLabeledField(
                      label: 'Cross axis',
                      child: StudioEnumSelect(
                        value: layout.crossAlignment,
                        values: SceneCrossAlignment.values,
                        onChanged: (value) => _applyOptions(cross: value),
                      ),
                    ),
                    StudioSwitchRow(
                      label: 'Wrap children',
                      value: layout.wrap,
                      onChanged: (value) => _applyOptions(wrap: value),
                    ),
                    StudioSwitchRow(
                      label: 'Clip content',
                      value: layout.clip,
                      onChanged: (value) => _applyOptions(clip: value),
                    ),
                  ],
                  StudioLabeledField(
                    label: 'Width mode',
                    child: StudioEnumSelect(
                      key: const ValueKey('layout-width-mode'),
                      value: sizing.widthMode,
                      values: modes,
                      onChanged: (value) => _applyOptions(widthMode: value),
                    ),
                  ),
                  StudioLabeledField(
                    label: 'Height mode',
                    child: StudioEnumSelect(
                      key: const ValueKey('layout-height-mode'),
                      value: sizing.heightMode,
                      values: modes,
                      onChanged: (value) => _applyOptions(heightMode: value),
                    ),
                  ),
                  StudioFieldRow(
                    left: _field('Fixed width'),
                    right: _field('Fixed height'),
                  ),
                ],
              ),
            ),
            const Divider(),
            StudioDisclosureSection(
              key: ValueKey('sizing-constraints-${node.id}-$editing'),
              triggerKey: const ValueKey('layout-size-constraints'),
              title: 'Size constraints',
              showTopDividerWhenExpanded: true,
              initiallyExpanded:
                  sizing.minWidth > 0 ||
                  sizing.minHeight > 0 ||
                  sizing.maxWidth != null ||
                  sizing.maxHeight != null ||
                  sizing.flex > 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  StudioFieldRow(
                    left: _field('Min width'),
                    right: _field('Min height'),
                  ),
                  StudioFieldRow(
                    left: _field('Max width'),
                    right: _field('Max height'),
                  ),
                  _field('Flex'),
                  const Text(
                    'Blank fixed sizes use the selected mode. Hug measures text or frame contents; fill shares the available space. Breakpoints use logical viewport width.',
                  ).xSmall().muted(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
