import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../model/studio_scenario.dart';
import '../ui/studio_condition_editor.dart';
import '../ui/studio_form.dart';
import '../ui/studio_form_values.dart';

class StudioStateGraph extends StatelessWidget {
  const StudioStateGraph({
    required this.editor,
    required this.dormant,
    required this.scenario,
    required this.onSelect,
    this.readOnly = false,
    super.key,
  });
  final SceneEditor editor;
  final bool dormant;
  final StudioPreviewScenario scenario;
  final void Function(bool, StudioPreviewScenario) onSelect;
  final bool readOnly;

  Future<void> _editTransition(BuildContext context, int? index) async {
    if (readOnly || editor.selectedIds.isEmpty || !editor.tryApplyDraft()) {
      return;
    }
    final node = editor.selectedNode;
    if (index != null && index >= node.transitions.length) return;
    final targetId = node.id;
    final result = await showOverlay<SceneStateTransition>(
      context,
      const DialogConfiguration(),
      builder: (_) => _TransitionDialog(
        initial: index == null ? null : node.transitions[index],
      ),
    ).future;
    if (result == null || !context.mounted || editor.isDisposed) return;
    final current = editor.document.nodes
        .where((entry) => entry.id == targetId)
        .firstOrNull;
    if (current == null) return;
    final rules = [...current.transitions];
    if (index == null) {
      rules.add(result);
    } else if (index < rules.length) {
      rules[index] = result;
    } else {
      return;
    }
    editor.updateNode(current.copyWith(transitions: rules));
  }

  void _removeTransition(String nodeId, int index) {
    if (readOnly || !editor.tryApplyDraft()) return;
    final current = editor.document.nodes
        .where((entry) => entry.id == nodeId)
        .firstOrNull;
    if (current == null || index >= current.transitions.length) return;
    editor.updateNode(
      current.copyWith(transitions: [...current.transitions]..removeAt(index)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = editor.selectedIds.isNotEmpty;
    final node = hasSelection ? editor.selectedNode : null;
    final transitions = node?.transitions ?? const <SceneStateTransition>[];
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('State flow · Select a state to preview')
              .small()
              .semiBold(),
          const Gap(8),
          _StatePreviewBar(
            dormant: dormant,
            scenario: scenario,
            onSelect: onSelect,
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: Text(
                  node == null
                      ? 'No selection · visual transitions'
                      : '${node.id} · visual transitions',
                ).small().semiBold(),
              ),
              OutlineButton(
                key: const ValueKey('graph-add-transition'),
                onPressed: readOnly || node == null
                    ? null
                    : () => _editTransition(context, null),
                child: const Text('Add transition').small(),
              ),
            ],
          ),
          const Gap(6),
          SizedBox(
            height: transitions.isEmpty ? 42 : 120,
            child: node == null
                ? const Text(
                    'Select a node to inspect or add visual transition rules.',
                  ).small().muted()
                : transitions.isEmpty
                ? const Text(
                    'Add an edge to animate a layer when its source and target conditions match.',
                  ).small().muted()
                : ListView(
                    children: [
                      for (var i = 0; i < transitions.length; i++)
                        _TransitionEdgeRow(
                          index: i,
                          transition: transitions[i],
                          onEdit: readOnly
                              ? null
                              : () => _editTransition(context, i),
                          onRemove: readOnly
                              ? null
                              : () => _removeTransition(node.id, i),
                        ),
                    ],
                  ),
          ),
          const Text(
            'Visual rules observe backend state. They do not start or change authentication.',
          ).small().muted(),
        ],
      ),
    );
  }
}

class _StatePreviewBar extends StatelessWidget {
  const _StatePreviewBar({
    required this.dormant,
    required this.scenario,
    required this.onSelect,
  });

  final bool dormant;
  final StudioPreviewScenario scenario;
  final void Function(bool, StudioPreviewScenario) onSelect;

  static const _states = [
    ('Dormant', true, StudioPreviewScenario.password),
    ('Login', false, StudioPreviewScenario.password),
    ('Submitting', false, StudioPreviewScenario.submitting),
    ('Success', false, StudioPreviewScenario.success),
    ('Error', false, StudioPreviewScenario.error),
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var i = 0; i < _states.length; i++) ...[
          if (i > 0) const Gap(6),
          Button(
            key: ValueKey('graph-${_states[i].$1}'),
            style:
                dormant == _states[i].$2 &&
                    (dormant || scenario == _states[i].$3)
                ? const ButtonStyle.primary()
                : const ButtonStyle.outline(),
            onPressed: () => onSelect(_states[i].$2, _states[i].$3),
            child: Text(_states[i].$1),
          ),
        ],
      ],
    ),
  );
}

class _TransitionEdgeRow extends StatelessWidget {
  const _TransitionEdgeRow({
    required this.index,
    required this.transition,
    required this.onEdit,
    required this.onRemove,
  });

  final int index;
  final SceneStateTransition transition;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: OutlineButton(
            key: ValueKey('graph-edge-$index'),
            onPressed: onEdit,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    getSceneConditionLabel(transition.source),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ).small(),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(LucideIcons.arrowRight, size: 16),
                ),
                Expanded(
                  child: Text(
                    getSceneConditionLabel(transition.target),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ).small(),
                ),
                const Gap(8),
                Text(transition.effect.name).small(),
              ],
            ),
          ),
        ),
        GhostButton(
          onPressed: onRemove,
          child: const Icon(LucideIcons.x, size: 14),
        ),
      ],
    ),
  );
}

class _TransitionDialog extends StatefulWidget {
  const _TransitionDialog({this.initial});
  final SceneStateTransition? initial;
  @override
  State<_TransitionDialog> createState() => _TransitionDialogState();
}

class _TransitionDialogState extends State<_TransitionDialog> {
  late SceneCondition _source =
      widget.initial?.source ??
      const ScenePredicateCondition(ScenePredicate.isAuthSubmitting);
  late SceneCondition _target =
      widget.initial?.target ??
      const ScenePredicateCondition(ScenePredicate.isAuthError);
  late SceneStateEffect _effect =
      widget.initial?.effect ?? SceneStateEffect.shake;
  late final _duration = TextEditingController(
    text: widget.initial?.timing.durationMs?.toString() ?? '',
  );
  late final _delay = TextEditingController(
    text: '${widget.initial?.timing.delayMs ?? 0}',
  );
  String? _error;
  @override
  void dispose() {
    _duration.dispose();
    _delay.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final duration = _duration.text.trim().isEmpty
          ? null
          : getIntegerInput('Duration', _duration.text);
      final delay = getIntegerInput('Delay', _delay.text);
      if ((duration != null &&
              (duration < 0 || duration > maxSceneMotionTimeMs)) ||
          delay < 0 ||
          delay > maxSceneMotionTimeMs) {
        throw const FormatException('Timing must be in 0..60000 ms.');
      }
      Navigator.of(context).pop(
        SceneStateTransition(
          source: _source,
          target: _target,
          effect: _effect,
          timing: SceneMotionTiming(
            durationMs: duration,
            delayMs: delay,
            curve: widget.initial?.timing.curve,
          ),
        ),
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Visual transition'),
    content: SizedBox(
      width: 600,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('From').small().semiBold(),
              const Gap(6),
              StudioConditionEditor(
                value: _source,
                onChanged: (value) => setState(() => _source = value),
              ),
              const Gap(16),
              const Text('To').small().semiBold(),
              const Gap(6),
              StudioConditionEditor(
                value: _target,
                onChanged: (value) => setState(() => _target = value),
              ),
              const Gap(16),
              StudioEnumSelect(
                key: const ValueKey('transition-effect'),
                value: _effect,
                values: SceneStateEffect.values,
                onChanged: (value) => setState(() => _effect = value),
              ),
              const Gap(12),
              StudioFieldRow(
                left: StudioFormField(
                  label: 'Duration ms',
                  controller: _duration,
                  inputKey: const ValueKey('transition-duration'),
                ),
                right: StudioFormField(
                  label: 'Delay ms',
                  controller: _delay,
                  inputKey: const ValueKey('transition-delay'),
                ),
              ),
              if (_error != null) ...[const Gap(8), StudioFormError(_error!)],
            ],
          ),
        ),
      ),
    ),
    actions: [
      OutlineButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      PrimaryButton(
        key: const ValueKey('save-transition'),
        onPressed: _save,
        child: const Text('Apply'),
      ),
    ],
  );
}
