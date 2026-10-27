import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'studio_form.dart';
import 'studio_state_labels.dart';

String getSceneConditionLabel(SceneCondition condition) => switch (condition) {
  ScenePredicateCondition(:final predicate) => getScenePredicateLabel(
    predicate,
  ),
  SceneNot(:final condition) => 'Not (${getSceneConditionLabel(condition)})',
  SceneAll(:final conditions) =>
    conditions.map(getSceneConditionLabel).join(' & '),
  SceneAny(:final conditions) =>
    conditions.map(getSceneConditionLabel).join(' | '),
};

/// One recursive composer for visibility and transition endpoint conditions.
class StudioConditionEditor extends StatelessWidget {
  const StudioConditionEditor({
    required this.value,
    required this.onChanged,
    super.key,
  });
  final SceneCondition value;
  final ValueChanged<SceneCondition> onChanged;
  @override
  Widget build(BuildContext context) {
    final kind = switch (value) {
      ScenePredicateCondition() => 'Predicate',
      SceneAll() => 'All',
      SceneAny() => 'Any',
      SceneNot() => 'Not',
    };
    final children = switch (value) {
      SceneAll(:final conditions) || SceneAny(:final conditions) => conditions,
      SceneNot(:final condition) => [condition],
      _ => <SceneCondition>[],
    };
    void updateChildren(List<SceneCondition> updated) => onChanged(
      kind == 'All'
          ? SceneAll(updated)
          : kind == 'Any'
          ? SceneAny(updated)
          : SceneNot(updated.single),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 115,
              child: StudioSelect<String>(
                value: kind,
                values: const ['Predicate', 'All', 'Any', 'Not'],
                formatValue: (value) => value,
                onChanged: (kind) => onChanged(switch (kind) {
                  'All' => SceneAll(children.isEmpty ? [value] : children),
                  'Any' => SceneAny(children.isEmpty ? [value] : children),
                  'Not' => SceneNot(value),
                  _ =>
                    value is ScenePredicateCondition
                        ? value
                        : const ScenePredicateCondition(
                            ScenePredicate.isAuthError,
                          ),
                }),
              ),
            ),
            const Gap(8),
            if (value case ScenePredicateCondition(:final predicate))
              Expanded(
                child: StudioEnumSelect(
                  value: predicate,
                  values: ScenePredicate.values,
                  formatValue: getScenePredicateLabel,
                  onChanged: (value) =>
                      onChanged(ScenePredicateCondition(value)),
                ),
              )
            else
              Expanded(
                child: Text(
                  kind == 'All'
                      ? 'Every condition'
                      : kind == 'Any'
                      ? 'At least one condition'
                      : 'Invert condition',
                ).small().muted(),
              ),
          ],
        ),
        if (children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < children.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: StudioConditionEditor(
                            value: children[index],
                            onChanged: (value) =>
                                updateChildren([...children]..[index] = value),
                          ),
                        ),
                        if (kind != 'Not' && children.length > 1)
                          GhostButton(
                            onPressed: () =>
                                updateChildren([...children]..removeAt(index)),
                            child: const Icon(LucideIcons.x, size: 14),
                          ),
                      ],
                    ),
                  ),
                if (kind != 'Not')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlineButton(
                      onPressed: () => updateChildren([
                        ...children,
                        const ScenePredicateCondition(
                          ScenePredicate.hasSelectedUser,
                        ),
                      ]),
                      child: const Text('Add condition').small(),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

Future<({SceneCondition? condition})?> editStudioCondition(
  BuildContext context,
  SceneCondition? initial,
) {
  var value =
      initial ?? const ScenePredicateCondition(ScenePredicate.isAuthError);
  return showOverlay<({SceneCondition? condition})>(
    context,
    const DialogConfiguration(),
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Visibility condition'),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: StudioConditionEditor(
                value: value,
                onChanged: (condition) => update(() => value = condition),
              ),
            ),
          ),
        ),
        actions: [
          GhostButton(
            onPressed: () => Navigator.of(context).pop((condition: null)),
            child: const Text('Always'),
          ),
          OutlineButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          PrimaryButton(
            key: const ValueKey('save-condition'),
            onPressed: () => Navigator.of(context).pop((condition: value)),
            child: const Text('Apply'),
          ),
        ],
      ),
    ),
  ).future;
}
