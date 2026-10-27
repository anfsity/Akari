import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theme_studio/src/studio_input.dart';
import 'package:theme_studio/src/studio_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default commands are unique and edits persist without losing unbound commands', () async {
    const defaults = StudioInputBindings();
    for (final command in StudioCommand.values) {
      expect(defaults.findConflict(command, defaults.getBinding(command)!), isNull);
    }
    SharedPreferences.setMockInitialValues({});
    const custom = StudioKeyBinding(LogicalKeyboardKey.keyQ, alt: true);
    await const StudioPreferences(input: StudioInputBindings(
      overrides: {StudioCommand.move: custom, StudioCommand.scale: null},
      panButton: kSecondaryMouseButton, wheelModifier: StudioWheelModifier.alt,
    )).save();
    final restored = (await StudioPreferences.load()).input;
    expect(restored.getBinding(StudioCommand.move), custom);
    expect(restored.getBinding(StudioCommand.scale), isNull);
    expect(restored.panButton, kSecondaryMouseButton);
    expect(restored.wheelModifier, StudioWheelModifier.alt);
    expect(restored.findConflict(StudioCommand.rotate, custom), StudioCommand.move);
  });

  test('corrupt and conflicting bindings fail at the storage boundary', () {
    for (final value in [
      {'keys': {}, 'panButton': kPrimaryMouseButton, 'wheelModifier': 'control'},
      {'keys': {}, 'panButton': kMiddleMouseButton, 'wheelModifier': 'unknown'},
      {'keys': {'unknown': null}, 'panButton': kMiddleMouseButton, 'wheelModifier': 'control'},
      StudioInputBindings(overrides: {StudioCommand.move: StudioCommand.save.defaultBinding}).encode(),
    ]) {
      expect(() => StudioInputBindings.decode(value), throwsFormatException);
    }
  });
}
