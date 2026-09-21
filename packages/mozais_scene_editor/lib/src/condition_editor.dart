import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

/// Edits a node's `visibleWhen` condition as a flat ANY/ALL rule list.
///
/// Conditions that nest deeper than one combinator level are shown read-only;
/// the model still supports them, but the simple builder does not author them.
class ConditionEditor extends StatelessWidget {
  const ConditionEditor({
    required this.condition,
    required this.onChanged,
    super.key,
  });

  final SceneCondition? condition;
  final ValueChanged<SceneCondition?> onChanged;

  @override
  Widget build(BuildContext context) {
    final condition = this.condition;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Always')),
            ButtonSegment(value: true, label: Text('Rule')),
          ],
          selected: {condition != null},
          onSelectionChanged: (selection) {
            if (selection.first) {
              onChanged(
                condition ??
                    const ScenePredicateCondition(ScenePredicate.isDormant),
              );
            } else {
              onChanged(null);
            }
          },
        ),
        if (condition != null) ...[
          const SizedBox(height: 8),
          _RuleBuilder(condition: condition, onChanged: onChanged),
        ],
      ],
    );
  }
}

class _RuleBuilder extends StatelessWidget {
  const _RuleBuilder({required this.condition, required this.onChanged});

  final SceneCondition condition;
  final ValueChanged<SceneCondition?> onChanged;

  @override
  Widget build(BuildContext context) {
    final draft = _flatten(condition);
    if (draft == null) {
      return Row(
        children: [
          const Expanded(
            child: Text('Nested condition. Edit it in the JSON file.'),
          ),
          TextButton(
            onPressed: () => onChanged(null),
            child: const Text('Clear'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Match'),
            const SizedBox(width: 8),
            DropdownButton<bool>(
              value: draft.any,
              onChanged: (value) =>
                  onChanged(_build(draft.copyWith(any: value ?? false))),
              items: const [
                DropdownMenuItem(value: false, child: Text('all of')),
                DropdownMenuItem(value: true, child: Text('any of')),
              ],
            ),
          ],
        ),
        for (var index = 0; index < draft.clauses.length; index++)
          _clauseRow(draft, index),
        TextButton.icon(
          onPressed: () => onChanged(_build(draft.withClause())),
          icon: const Icon(Icons.add),
          label: const Text('Add clause'),
        ),
      ],
    );
  }

  Widget _clauseRow(_RuleDraft draft, int index) {
    final clause = draft.clauses[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<ScenePredicate>(
              isExpanded: true,
              value: clause.predicate,
              onChanged: (value) => onChanged(
                _build(draft.withClauseAt(index, clause.copyWith(predicate: value))),
              ),
              items: [
                for (final predicate in ScenePredicate.values)
                  DropdownMenuItem(value: predicate, child: Text(predicate.name)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<bool>(
            value: clause.negated,
            onChanged: (value) => onChanged(
              _build(
                draft.withClauseAt(index, clause.copyWith(negated: value ?? false)),
              ),
            ),
            items: const [
              DropdownMenuItem(value: false, child: Text('is')),
              DropdownMenuItem(value: true, child: Text('is not')),
            ],
          ),
          IconButton(
            tooltip: 'Remove clause',
            onPressed: draft.clauses.length == 1
                ? null
                : () => onChanged(_build(draft.withoutClause(index))),
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _Clause {
  const _Clause({required this.predicate, required this.negated});

  final ScenePredicate predicate;
  final bool negated;

  _Clause copyWith({ScenePredicate? predicate, bool? negated}) {
    return _Clause(
      predicate: predicate ?? this.predicate,
      negated: negated ?? this.negated,
    );
  }
}

class _RuleDraft {
  const _RuleDraft({required this.any, required this.clauses});

  final bool any;
  final List<_Clause> clauses;

  _RuleDraft copyWith({bool? any, List<_Clause>? clauses}) {
    return _RuleDraft(any: any ?? this.any, clauses: clauses ?? this.clauses);
  }

  _RuleDraft withClause() {
    return copyWith(
      clauses: [
        ...clauses,
        const _Clause(predicate: ScenePredicate.isDormant, negated: false),
      ],
    );
  }

  _RuleDraft withClauseAt(int index, _Clause clause) {
    return copyWith(
      clauses: [
        for (var i = 0; i < clauses.length; i++)
          if (i == index) clause else clauses[i],
      ],
    );
  }

  _RuleDraft withoutClause(int index) {
    return copyWith(
      clauses: [
        for (var i = 0; i < clauses.length; i++)
          if (i != index) clauses[i],
      ],
    );
  }
}

_RuleDraft? _flatten(SceneCondition condition) {
  if (condition is SceneAny) {
    final clauses = _flattenList(condition.conditions);
    if (clauses != null) {
      return _RuleDraft(any: true, clauses: clauses);
    }
  }
  if (condition is SceneAll) {
    final clauses = _flattenList(condition.conditions);
    if (clauses != null) {
      return _RuleDraft(any: false, clauses: clauses);
    }
  }
  final leaf = _flattenLeaf(condition);
  return leaf == null ? null : _RuleDraft(any: false, clauses: [leaf]);
}

List<_Clause>? _flattenList(List<SceneCondition> conditions) {
  final clauses = <_Clause>[];
  for (final condition in conditions) {
    final clause = _flattenLeaf(condition);
    if (clause == null) {
      return null;
    }
    clauses.add(clause);
  }
  return clauses;
}

_Clause? _flattenLeaf(SceneCondition condition) {
  if (condition is ScenePredicateCondition) {
    return _Clause(predicate: condition.predicate, negated: false);
  }
  if (condition is SceneNot) {
    final inner = condition.condition;
    if (inner is ScenePredicateCondition) {
      return _Clause(predicate: inner.predicate, negated: true);
    }
  }
  return null;
}

SceneCondition _build(_RuleDraft draft) {
  final leaves = <SceneCondition>[
    for (final clause in draft.clauses)
      clause.negated
          ? SceneNot(ScenePredicateCondition(clause.predicate))
          : ScenePredicateCondition(clause.predicate),
  ];
  if (leaves.length == 1) {
    return leaves.single;
  }
  return draft.any ? SceneAny(leaves) : SceneAll(leaves);
}
