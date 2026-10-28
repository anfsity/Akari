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
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Visible when').small().muted(),
          const Gap(6),
          StudioSelect<String>(
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
          const Gap(8),
          OutlineButton(
            key: const ValueKey('edit-visibility-condition'),
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
            Row(
              children: [
                const Expanded(child: Text('Invert condition')),
                Switch(
                  value: condition is SceneNot,
                  onChanged: (invert) => _updateNode(
                    (node) => node.copyWith(
                      visibleWhen: invert
                          ? SceneNot(ScenePredicateCondition(predicate))
                          : ScenePredicateCondition(predicate),
                    ),
                  ),
                ),
              ],
            ),
          const Gap(12),
          const Text('On state entry').small().semiBold(),
          const Gap(8),
          for (final rule in node.stateEffects.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${getScenePredicateLabel(rule.key)} → ${rule.value.name}',
                    ).small(),
                  ),
                  GhostButton(
                    onPressed: () => _updateNode(
                      (node) => node.copyWith(
                        stateEffects: {...node.stateEffects}..remove(rule.key),
                      ),
                    ),
                    child: const Icon(LucideIcons.x, size: 14),
                  ),
                ],
              ),
            ),
          StudioEnumSelect(
            key: const ValueKey('state-trigger'),
            value: _trigger,
            values: ScenePredicate.values,
            formatValue: getScenePredicateLabel,
            onChanged: (value) => setState(() => _trigger = value),
          ),
          const Gap(8),
          StudioEnumSelect(
            key: const ValueKey('state-effect'),
            value: _effect,
            values: SceneStateEffect.values,
            onChanged: (value) => setState(() => _effect = value),
          ),
          const Gap(8),
          OutlineButton(
            key: const ValueKey('add-state-effect'),
            onPressed: () => _updateNode(
              (node) => node.copyWith(
                stateEffects: {...node.stateEffects, _trigger: _effect},
              ),
            ),
            child: const Text('Add / update response'),
          ),
          const Gap(8),
          const Text('Responses use node timing and respect reduced motion.')
              .small()
              .muted(),
        ],
      ),
    );
  }
}
