import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import 'editor_strings.dart';

/// Edits a node's `visibleWhen` condition as a flat ANY/ALL rule list.
///
/// Presets cover the common states; the rule builder offers the full predicate
/// vocabulary with human labels. Conditions that nest deeper than one
/// combinator level are shown read-only under Advanced; the model still
/// supports them, but the simple builder does not author them.
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
    final strings = EditorStringsScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(strings.always)),
            ButtonSegment(value: true, label: Text(strings.rule)),
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
          const SizedBox(height: 12),
          _Presets(onChanged: onChanged),
          const SizedBox(height: 12),
          _RuleBuilder(condition: condition, onChanged: onChanged),
        ],
      ],
    );
  }
}

class _Presets extends StatelessWidget {
  const _Presets({required this.onChanged});

  final ValueChanged<SceneCondition?> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    final presets = <(String, SceneCondition)>[
      (
        strings.asleep,
        const ScenePredicateCondition(ScenePredicate.isDormant),
      ),
      (
        strings.awake,
        const SceneNot(ScenePredicateCondition(ScenePredicate.isDormant)),
      ),
      (
        strings.authenticating,
        const SceneAny([
          ScenePredicateCondition(ScenePredicate.isAuthPrompting),
          ScenePredicateCondition(ScenePredicate.isAuthSubmitting),
        ]),
      ),
      (
        strings.errorState,
        const SceneAny([
          ScenePredicateCondition(ScenePredicate.isAuthError),
          ScenePredicateCondition(ScenePredicate.isServiceUnavailable),
          ScenePredicateCondition(ScenePredicate.isSessionFailed),
          ScenePredicateCondition(ScenePredicate.hasPowerError),
        ]),
      ),
      (
        strings.userSelected,
        const ScenePredicateCondition(ScenePredicate.hasSelectedUser),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.presets, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (label, preset) in presets)
              ActionChip(
                label: Text(label),
                onPressed: () => onChanged(preset),
              ),
          ],
        ),
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
    final strings = EditorStringsScope.of(context);
    final draft = _flatten(condition);
    if (draft == null) {
      return _Advanced(condition: condition, onChanged: onChanged);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(strings.match),
            const SizedBox(width: 8),
            DropdownButton<bool>(
              value: draft.any,
              onChanged: (value) =>
                  onChanged(_build(draft.copyWith(any: value ?? false))),
              items: [
                DropdownMenuItem(value: false, child: Text(strings.allOf)),
                DropdownMenuItem(value: true, child: Text(strings.anyOf)),
              ],
            ),
          ],
        ),
        for (var index = 0; index < draft.clauses.length; index++)
          _clauseRow(strings, draft, index),
        TextButton.icon(
          onPressed: () => onChanged(_build(draft.withClause())),
          icon: const Icon(Icons.add),
          label: Text(strings.addClause),
        ),
      ],
    );
  }

  Widget _clauseRow(EditorStrings strings, _RuleDraft draft, int index) {
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
                _build(
                  draft.withClauseAt(index, clause.copyWith(predicate: value)),
                ),
              ),
              items: [
                for (final predicate in ScenePredicate.values)
                  DropdownMenuItem(
                    value: predicate,
                    child: Text(strings.predicateLabel(predicate)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<bool>(
            value: clause.negated,
            onChanged: (value) => onChanged(
              _build(
                draft.withClauseAt(
                  index,
                  clause.copyWith(negated: value ?? false),
                ),
              ),
            ),
            items: [
              DropdownMenuItem(value: false, child: Text(strings.isOperator)),
              DropdownMenuItem(value: true, child: Text(strings.isNotOperator)),
            ],
          ),
          IconButton(
            tooltip: strings.removeClause,
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

/// Read-only view of a condition the flat builder cannot represent.
class _Advanced extends StatelessWidget {
  const _Advanced({required this.condition, required this.onChanged});

  final SceneCondition condition;
  final ValueChanged<SceneCondition?> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(strings.advanced),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _describe(strings, condition),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            strings.nestedCondition,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => onChanged(null),
            child: Text(strings.clear),
          ),
        ),
      ],
    );
  }
}

String _describe(EditorStrings strings, SceneCondition condition) {
  return switch (condition) {
    ScenePredicateCondition(:final predicate) => strings.predicateLabel(
      predicate,
    ),
    SceneAll(:final conditions) =>
      'all(${conditions.map((child) => _describe(strings, child)).join(', ')})',
    SceneAny(:final conditions) =>
      'any(${conditions.map((child) => _describe(strings, child)).join(', ')})',
    SceneNot(:final condition) => 'not(${_describe(strings, condition)})',
  };
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
