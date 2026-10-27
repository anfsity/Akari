import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

/// One command catalog drives dispatch, settings, and shortcut labels.
/// Document commands remain scoped to the canvas so text fields retain their
/// own editing shortcuts. Workspace commands also work from the inspector.
enum StudioCommand {
  save(
    'Save scene',
    'Project',
    StudioKeyBinding(LogicalKeyboardKey.keyS, control: true),
  ),
  settings(
    'Open settings',
    'Project',
    StudioKeyBinding(LogicalKeyboardKey.comma, control: true),
  ),
  undo(
    'Undo',
    'Edit',
    StudioKeyBinding(LogicalKeyboardKey.keyZ, control: true),
  ),
  redo(
    'Redo',
    'Edit',
    StudioKeyBinding(LogicalKeyboardKey.keyZ, control: true, shift: true),
  ),
  duplicate(
    'Duplicate',
    'Edit',
    StudioKeyBinding(LogicalKeyboardKey.keyD, control: true),
  ),
  delete('Delete', 'Edit', StudioKeyBinding(LogicalKeyboardKey.delete)),
  selectAll(
    'Select all',
    'Edit',
    StudioKeyBinding(LogicalKeyboardKey.keyA, control: true),
  ),
  group(
    'Group',
    'Edit',
    StudioKeyBinding(LogicalKeyboardKey.keyG, control: true),
  ),
  ungroup(
    'Ungroup',
    'Edit',
    StudioKeyBinding(LogicalKeyboardKey.keyG, control: true, shift: true),
  ),
  move('Move / resize', 'Tools', StudioKeyBinding(LogicalKeyboardKey.keyV)),
  scale('Scale', 'Tools', StudioKeyBinding(LogicalKeyboardKey.keyK)),
  rotate('Rotate', 'Tools', StudioKeyBinding(LogicalKeyboardKey.keyR)),
  rotate3d(
    'Rotate in 3D',
    'Tools',
    StudioKeyBinding(LogicalKeyboardKey.keyR, shift: true),
  ),
  hand('Hand tool', 'Tools', StudioKeyBinding(LogicalKeyboardKey.keyH)),
  temporaryPan(
    'Hold to pan',
    'Navigation',
    StudioKeyBinding(LogicalKeyboardKey.space),
  ),
  fit(
    'Fit canvas',
    'Navigation',
    StudioKeyBinding(LogicalKeyboardKey.digit1, shift: true),
  ),
  actualSize(
    'Actual size',
    'Navigation',
    StudioKeyBinding(LogicalKeyboardKey.digit0, shift: true),
  ),
  zoomIn(
    'Zoom in',
    'Navigation',
    StudioKeyBinding(LogicalKeyboardKey.equal, control: true),
  ),
  zoomOut(
    'Zoom out',
    'Navigation',
    StudioKeyBinding(LogicalKeyboardKey.minus, control: true),
  ),
  sidebar(
    'Toggle project panel',
    'Workspace',
    StudioKeyBinding(LogicalKeyboardKey.keyB, control: true),
  ),
  inspector(
    'Toggle properties panel',
    'Workspace',
    StudioKeyBinding(LogicalKeyboardKey.keyB, control: true, shift: true),
  ),
  presentation(
    'Presentation',
    'Workspace',
    StudioKeyBinding(LogicalKeyboardKey.keyP, control: true, shift: true),
  ),
  timeline(
    'Toggle timeline',
    'Workspace',
    StudioKeyBinding(LogicalKeyboardKey.keyT, control: true),
  ),
  stateGraph(
    'Toggle state graph',
    'Workspace',
    StudioKeyBinding(LogicalKeyboardKey.keyJ, control: true),
  ),
  compare(
    'Compare displays',
    'Workspace',
    StudioKeyBinding(LogicalKeyboardKey.keyM, control: true),
  ),
  rulers(
    'Toggle rulers',
    'Workspace',
    StudioKeyBinding(LogicalKeyboardKey.keyR, control: true),
  ),
  guides(
    'Toggle smart guides',
    'Workspace',
    StudioKeyBinding(LogicalKeyboardKey.semicolon, control: true),
  ),
  preview(
    'Play / edit canvas',
    'Workspace',
    StudioKeyBinding(LogicalKeyboardKey.enter, control: true),
  ),
  nudgeLeft(
    'Nudge left',
    'Geometry',
    StudioKeyBinding(LogicalKeyboardKey.arrowLeft),
  ),
  nudgeRight(
    'Nudge right',
    'Geometry',
    StudioKeyBinding(LogicalKeyboardKey.arrowRight),
  ),
  nudgeUp('Nudge up', 'Geometry', StudioKeyBinding(LogicalKeyboardKey.arrowUp)),
  nudgeDown(
    'Nudge down',
    'Geometry',
    StudioKeyBinding(LogicalKeyboardKey.arrowDown),
  ),
  fastLeft(
    'Nudge left × 10',
    'Geometry',
    StudioKeyBinding(LogicalKeyboardKey.arrowLeft, shift: true),
  ),
  fastRight(
    'Nudge right × 10',
    'Geometry',
    StudioKeyBinding(LogicalKeyboardKey.arrowRight, shift: true),
  ),
  fastUp(
    'Nudge up × 10',
    'Geometry',
    StudioKeyBinding(LogicalKeyboardKey.arrowUp, shift: true),
  ),
  fastDown(
    'Nudge down × 10',
    'Geometry',
    StudioKeyBinding(LogicalKeyboardKey.arrowDown, shift: true),
  ),
  addText('Add text', 'Create', StudioKeyBinding(LogicalKeyboardKey.keyT)),
  addShape(
    'Add rectangle',
    'Create',
    StudioKeyBinding(LogicalKeyboardKey.keyU),
  ),
  addFrame('Add frame', 'Create', StudioKeyBinding(LogicalKeyboardKey.keyF));

  const StudioCommand(this.label, this.category, this.defaultBinding);
  final String label;
  final String category;
  final StudioKeyBinding defaultBinding;
}

class StudioKeyBinding {
  const StudioKeyBinding(
    this.key, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });
  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;

  SingleActivator getActivator({bool repeats = true}) => SingleActivator(
    key,
    control: control,
    shift: shift,
    alt: alt,
    meta: meta,
    includeRepeats: repeats,
  );

  bool isPressed(KeyEvent event) =>
      getActivator().accepts(event, HardwareKeyboard.instance);

  String getLabel() => [
    if (control) 'Ctrl',
    if (alt) 'Alt',
    if (shift) 'Shift',
    if (meta) 'Super',
    key.keyLabel.isEmpty ? key.debugName ?? '${key.keyId}' : key.keyLabel,
  ].join('+');

  Map<String, Object> encode() => {
    'key': key.keyId,
    'control': control,
    'shift': shift,
    'alt': alt,
    'meta': meta,
  };

  factory StudioKeyBinding.decode(Object? value) {
    if (value is! Map ||
        value['key'] is! int ||
        [
          'control',
          'shift',
          'alt',
          'meta',
        ].any((name) => value[name] is! bool)) {
      throw const FormatException('Invalid keyboard binding.');
    }
    final key = LogicalKeyboardKey.findKeyByKeyId(value['key'] as int);
    if (key == null || isModifierKey(key)) {
      throw const FormatException('Choose a non-modifier key.');
    }
    return StudioKeyBinding(
      key,
      control: value['control'] as bool,
      shift: value['shift'] as bool,
      alt: value['alt'] as bool,
      meta: value['meta'] as bool,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StudioKeyBinding &&
      key == other.key &&
      control == other.control &&
      shift == other.shift &&
      alt == other.alt &&
      meta == other.meta;
  @override
  int get hashCode => Object.hash(key, control, shift, alt, meta);
}

bool isModifierKey(LogicalKeyboardKey key) => const [
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
].contains(key);

enum StudioWheelModifier { control, alt, meta, none }

class StudioInputBindings {
  const StudioInputBindings({
    this.overrides = const {},
    this.panButton = kMiddleMouseButton,
    this.wheelModifier = StudioWheelModifier.control,
  });
  final Map<StudioCommand, StudioKeyBinding?> overrides;
  final int panButton;
  final StudioWheelModifier wheelModifier;

  StudioKeyBinding? getBinding(StudioCommand command) =>
      overrides.containsKey(command)
      ? overrides[command]
      : command.defaultBinding;

  StudioCommand? findCommand(KeyEvent event) {
    for (final command in StudioCommand.values) {
      if (getBinding(command)?.isPressed(event) ?? false) return command;
    }
    return null;
  }

  StudioCommand? findConflict(StudioCommand command, StudioKeyBinding binding) {
    for (final candidate in StudioCommand.values) {
      if (candidate != command && getBinding(candidate) == binding) {
        return candidate;
      }
    }
    return null;
  }

  bool isZoomGesture() => switch (wheelModifier) {
    StudioWheelModifier.control => HardwareKeyboard.instance.isControlPressed,
    StudioWheelModifier.alt => HardwareKeyboard.instance.isAltPressed,
    StudioWheelModifier.meta => HardwareKeyboard.instance.isMetaPressed,
    StudioWheelModifier.none => true,
  };

  Map<String, Object> encode() => {
    'keys': {
      for (final entry in overrides.entries)
        entry.key.name: entry.value?.encode(),
    },
    'panButton': panButton,
    'wheelModifier': wheelModifier.name,
  };

  factory StudioInputBindings.decode(Object? value) {
    if (value == null) return const StudioInputBindings();
    if (value is! Map ||
        value['keys'] is! Map ||
        !const {
          kMiddleMouseButton,
          kSecondaryMouseButton,
        }.contains(value['panButton']) ||
        !StudioWheelModifier.values.any(
          (modifier) => modifier.name == value['wheelModifier'],
        )) {
      throw const FormatException('Invalid mouse and keyboard settings.');
    }
    final overrides = <StudioCommand, StudioKeyBinding?>{};
    for (final entry in (value['keys'] as Map).entries) {
      final command = StudioCommand.values
          .where((command) => command.name == entry.key)
          .firstOrNull;
      if (command == null) {
        throw const FormatException('Unknown shortcut command.');
      }
      overrides[command] = entry.value == null
          ? null
          : StudioKeyBinding.decode(entry.value);
    }
    final result = StudioInputBindings(
      overrides: overrides,
      panButton: value['panButton'] as int,
      wheelModifier: StudioWheelModifier.values.byName(
        value['wheelModifier'] as String,
      ),
    );
    for (final command in StudioCommand.values) {
      final binding = result.getBinding(command);
      if (binding != null && result.findConflict(command, binding) != null) {
        throw FormatException('Duplicate shortcut: ${binding.getLabel()}.');
      }
    }
    return result;
  }
}
