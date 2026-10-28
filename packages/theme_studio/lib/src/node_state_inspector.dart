import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_form.dart';
import 'studio_condition_editor.dart';
import 'studio_state_labels.dart';

class NodeStateInspector extends StatefulWidget {
  const NodeStateInspector({required this.editor, super.key});
  final SceneEditor editor;
  @override
  State<NodeStateInspector> createState() => _NodeStateInspectorState();
}

class _NodeStateInspectorState extends State<NodeStateInspector> {
  ScenePredicate _trigger = ScenePredicate.isAuthError;
  SceneStateEffect _effect = SceneStateEffect.shake;

  void _updateNode(SceneNode Function(SceneNode) update) {
    if (!widget.editor.applyDraft()) return;
    widget.editor.updateNode(update(widget.editor.selectedNode));
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.editor.selectedNode;
    final condition = node.visibleWhen;
    final predicate = switch (condition) {
      ScenePredicateCondition(:final predicate) => predicate,
      SceneNot(condition: ScenePredicateCondition(:final predicate)) =>
        predicate,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        StudioLabeledField(
          label: 'Visible when',
          child: StudioSelect<String>(
            key: const ValueKey('state-visibility'),
            value: condition == null ? 'always' : predicate?.name,
            values: [
              'always',
              for (final value in ScenePredicate.values) value.name,
            ],
            formatValue: (value) => value == 'always'
                ? 'Always'
                : getScenePredicateLabel(ScenePredicate.values.byName(value)),
            placeholder: const Text('Custom condition (preserved)'),
            onChanged: (value) => _updateNode(
              (node) => node.copyWith(
                visibleWhen: value == 'always'
                    ? null
                    : ScenePredicateCondition(
                        ScenePredicate.values.byName(value),
                      ),
              ),
            ),
          ),
        ),
        OutlineButton(
          key: const ValueKey('edit-visibility-condition'),
          density: ButtonDensity.dense,
          onPressed: () async {
            if (!widget.editor.applyDraft()) return;
            final result = await editStudioCondition(context, condition);
            if (!mounted || result == null) return;
            _updateNode(
              (node) => node.copyWith(visibleWhen: result.condition),
            );
          },
          child: const Text('Edit compound condition').small(),
        ),
        if (predicate != null)
          StudioSwitchRow(
            label: 'Invert condition',
            value: condition is SceneNot,
            onChanged: (invert) => _updateNode(
              (node) => node.copyWith(
                visibleWhen: invert
                    ? SceneNot(ScenePredicateCondition(predicate))
                    : ScenePredicateCondition(predicate),
              ),
            ),
          ),
        const Divider(),
        StudioFormSection(
          title: 'On state entry',
          spacing: 8,
          children: [
            for (final rule in node.stateEffects.entries)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${getScenePredicateLabel(rule.key)} → ${rule.value.name}',
                    ).small(),
                  ),
                  GhostButton(
                    density: ButtonDensity.iconDense,
                    onPressed: () => _updateNode(
                      (node) => node.copyWith(
                        stateEffects: {...node.stateEffects}..remove(rule.key),
                      ),
                    ),
                    child: const Icon(LucideIcons.x, size: 14),
                  ),
                ],
              ),
            StudioEnumSelect(
              key: const ValueKey('state-trigger'),
              value: _trigger,
              values: ScenePredicate.values,
              formatValue: getScenePredicateLabel,
              onChanged: (value) => setState(() => _trigger = value),
            ),
            StudioEnumSelect(
              key: const ValueKey('state-effect'),
              value: _effect,
              values: SceneStateEffect.values,
              onChanged: (value) => setState(() => _effect = value),
            ),
            OutlineButton(
              key: const ValueKey('add-state-effect'),
              density: ButtonDensity.dense,
              onPressed: () => _updateNode(
                (node) => node.copyWith(
                  stateEffects: {...node.stateEffects, _trigger: _effect},
                ),
              ),
              child: const Text('Add / update response').small(),
            ),
            const Text('Responses use node timing and respect reduced motion.')
                .xSmall()
                .muted(),
          ],
        ),
      ],
    );
  }
}
