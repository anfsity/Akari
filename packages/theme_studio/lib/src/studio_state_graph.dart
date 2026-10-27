import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_condition_editor.dart';
import 'studio_form.dart';
import 'studio_form_values.dart';
import 'studio_preview_host.dart';

class StudioStateGraph extends StatelessWidget {
  const StudioStateGraph({
    required this.editor,
    required this.dormant,
    required this.scenario,
    required this.onSelect,
    super.key,
  });
  final SceneEditor editor;
  final bool dormant;
  final StudioPreviewScenario scenario;
  final void Function(bool, StudioPreviewScenario) onSelect;

  Widget _state(String label, bool dormant, StudioPreviewScenario scenario) =>
      Button(
        key: ValueKey('graph-$label'),
        style: this.dormant == dormant && (dormant || this.scenario == scenario)
            ? const ButtonStyle.primary()
            : const ButtonStyle.outline(),
        onPressed: () => onSelect(dormant, scenario),
        child: Text(label),
      );
  Future<void> _editTransition(BuildContext context, int? index) async {
    if (!editor.applyDraft()) return;
    final node = editor.selectedNode;
    final result = await showOverlay<SceneStateTransition>(
      context,
      const DialogConfiguration(),
      builder: (_) => _TransitionDialog(
        initial: index == null ? null : node.transitions[index],
      ),
    ).future;
    if (result == null || !context.mounted) return;
    final rules = [...node.transitions];
    if (index == null) {
      rules.add(result);
    } else {
      rules[index] = result;
    }
    editor.updateNode(node.copyWith(transitions: rules));
  }

  @override
  Widget build(BuildContext context) {
    final node = editor.selectedNode;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('State flow · Select a state to preview')
              .small()
              .semiBold(),
          const Gap(8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _state('Dormant', true, StudioPreviewScenario.password),
                const Gap(6),
                _state('Login', false, StudioPreviewScenario.password),
                const Gap(6),
                _state('Submitting', false, StudioPreviewScenario.submitting),
                const Gap(6),
                _state('Success', false, StudioPreviewScenario.success),
                const Gap(6),
                _state('Error', false, StudioPreviewScenario.error),
              ],
            ),
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: Text('${node.id} · visual transitions')
                    .small()
                    .semiBold(),
              ),
              OutlineButton(
                key: const ValueKey('graph-add-transition'),
                onPressed: () => _editTransition(context, null),
                child: const Text('Add transition').small(),
              ),
            ],
          ),
          const Gap(6),
          SizedBox(
            height: node.transitions.isEmpty ? 42 : 120,
            child: node.transitions.isEmpty
                ? const Text(
                    'Add an edge to animate a layer when its source and target conditions match.',
                  ).small().muted()
                : ListView(
                    children: [
                      for (var i = 0; i < node.transitions.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlineButton(
                                  key: ValueKey('graph-edge-$i'),
                                  onPressed: () => _editTransition(context, i),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          getSceneConditionLabel(
                                            node.transitions[i].from,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ).small(),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: Icon(
                                          LucideIcons.arrowRight,
                                          size: 16,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          getSceneConditionLabel(
                                            node.transitions[i].to,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ).small(),
                                      ),
                                      const Gap(8),
                                      Text(node.transitions[i].effect.name)
                                          .small(),
                                    ],
                                  ),
                                ),
                              ),
                              GhostButton(
                                onPressed: () => editor.updateNode(
                                  node.copyWith(
                                    transitions: [...node.transitions]
                                      ..removeAt(i),
                                  ),
                                ),
                                child: const Icon(LucideIcons.x, size: 14),
                              ),
                            ],
                          ),
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

class _TransitionDialog extends StatefulWidget {
  const _TransitionDialog({this.initial});
  final SceneStateTransition? initial;
  @override
  State<_TransitionDialog> createState() => _TransitionDialogState();
}

class _TransitionDialogState extends State<_TransitionDialog> {
  late SceneCondition _from =
      widget.initial?.from ??
      const ScenePredicateCondition(ScenePredicate.isAuthSubmitting);
  late SceneCondition _to =
      widget.initial?.to ??
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
      if ((duration != null && (duration < 0 || duration > 60000)) ||
          delay < 0 ||
          delay > 60000) {
        throw const FormatException('Timing must be in 0..60000 ms.');
      }
      Navigator.of(context).pop(
        SceneStateTransition(
          from: _from,
          to: _to,
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
                value: _from,
                onChanged: (value) => setState(() => _from = value),
              ),
              const Gap(16),
              const Text('To').small().semiBold(),
              const Gap(6),
              StudioConditionEditor(
                value: _to,
                onChanged: (value) => setState(() => _to = value),
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
              if (_error != null) Text(_error!).small(),
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
