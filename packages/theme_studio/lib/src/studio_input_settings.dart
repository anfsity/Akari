import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'studio_form.dart';
import 'studio_input.dart';

class StudioInputSettings extends StatefulWidget {
  const StudioInputSettings({
    required this.value,
    required this.onChanged,
    super.key,
  });
  final StudioInputBindings value;
  final ValueChanged<StudioInputBindings> onChanged;
  @override
  State<StudioInputSettings> createState() => _StudioInputSettingsState();
}

class _StudioInputSettingsState extends State<StudioInputSettings> {
  final _capture = FocusNode(debugLabel: 'Shortcut recorder');
  StudioCommand? _recording;
  String _query = '';
  String? _error;

  void _update(
    StudioCommand command,
    StudioKeyBinding? binding, {
    bool reset = false,
  }) {
    final overrides = {...widget.value.overrides};
    reset ? overrides.remove(command) : overrides[command] = binding;
    final updated = StudioInputBindings(
      overrides: overrides,
      panButton: widget.value.panButton,
      wheelModifier: widget.value.wheelModifier,
    );
    final candidate = updated.getBinding(command);
    final conflict = candidate == null
        ? null
        : updated.findConflict(command, candidate);
    if (conflict != null) {
      setState(
        () => _error =
            '${candidate!.getLabel()} is assigned to ${conflict.label}. Clear that binding first.',
      );
      return;
    }
    setState(() {
      _recording = null;
      _error = null;
    });
    widget.onChanged(updated);
  }

  KeyEventResult _record(FocusNode node, KeyEvent event) {
    if (_recording == null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent || isModifierKey(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _recording = null);
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    _update(
      _recording!,
      StudioKeyBinding(
        event.logicalKey,
        control: keyboard.isControlPressed,
        shift: keyboard.isShiftPressed,
        alt: keyboard.isAltPressed,
        meta: keyboard.isMetaPressed,
      ),
    );
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _capture,
    onKeyEvent: _record,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Mouse navigation').semiBold(),
        const Gap(12),
        StudioSelect<int>(
          key: const ValueKey('mouse-pan-button'),
          value: widget.value.panButton,
          values: const [kMiddleMouseButton, kSecondaryMouseButton],
          label: 'Drag to pan',
          formatValue: (value) =>
              value == kMiddleMouseButton ? 'Middle button' : 'Right button',
          onChanged: (value) => widget.onChanged(
            StudioInputBindings(
              overrides: widget.value.overrides,
              panButton: value,
              wheelModifier: widget.value.wheelModifier,
            ),
          ),
        ),
        const Gap(8),
        StudioEnumSelect(
          key: const ValueKey('mouse-wheel-modifier'),
          label: 'Wheel zoom',
          value: widget.value.wheelModifier,
          values: StudioWheelModifier.values,
          formatValue: (value) => value == StudioWheelModifier.none
              ? 'Wheel without modifier'
              : '${value.name} + wheel',
          onChanged: (value) => widget.onChanged(
            StudioInputBindings(
              overrides: widget.value.overrides,
              panButton: widget.value.panButton,
              wheelModifier: value,
            ),
          ),
        ),
        const Gap(12),
        const Text(
          'Primary drag: move or resize · Shift-click: multiple selection · '
          'Shift-resize: preserve proportions · Alt-drag: bypass snapping · '
          'Double-click text: edit · Wheel without the zoom modifier: pan.',
        ).small().muted(),
        const Gap(24),
        Row(
          children: [
            const Expanded(child: Text('Keyboard shortcuts')),
            GhostButton(
              key: const ValueKey('reset-shortcuts'),
              onPressed: () {
                setState(() {
                  _recording = null;
                  _error = null;
                });
                widget.onChanged(const StudioInputBindings());
              },
              child: const Text('Reset all').small(),
            ),
          ],
        ),
        const Gap(8),
        const Text(
          'Click a binding, then press a key combination. Escape cancels. '
          'Bindings are saved when you apply settings. Text inputs keep their normal editing shortcuts.',
        ).small().muted(),
        const Gap(12),
        TextField(
          key: const ValueKey('shortcut-search'),
          placeholder: const Text('Search commands'),
          onChanged: (value) => setState(() => _query = value.toLowerCase()),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: StudioFormError(_error!),
          ),
        for (final category
            in StudioCommand.values
                .map((command) => command.category)
                .toSet()) ...[
          if (StudioCommand.values.any(
            (command) =>
                command.category == category &&
                command.label.toLowerCase().contains(_query),
          ))
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 6),
              child: Text(category).small().muted(),
            ),
          for (final command in StudioCommand.values.where(
            (command) =>
                command.category == category &&
                command.label.toLowerCase().contains(_query),
          ))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(command.label).small()),
                  const Gap(8),
                  OutlineButton(
                    key: ValueKey('bind-${command.name}'),
                    onPressed: () {
                      setState(() {
                        _recording = command;
                        _error = null;
                      });
                      _capture.requestFocus();
                    },
                    child: Text(
                      _recording == command
                          ? 'Press keys…'
                          : widget.value.getBinding(command)?.getLabel() ??
                                'Unbound',
                    ).small(),
                  ),
                  GhostButton(
                    key: ValueKey('clear-${command.name}'),
                    onPressed: () => _update(command, null),
                    child: const Icon(LucideIcons.x, size: 14),
                  ),
                  GhostButton(
                    key: ValueKey('reset-${command.name}'),
                    onPressed: () => _update(command, null, reset: true),
                    child: const Icon(LucideIcons.rotateCcw, size: 14),
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}
