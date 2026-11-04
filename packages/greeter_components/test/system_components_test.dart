import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter_components/greeter_components.dart';
import 'package:theme_sdk/theme_sdk.dart';

void main() {
  testWidgets('power actions dispatch and disable while executing', (
    tester,
  ) async {
    final actions = <PowerAction>[];
    Widget build(PowerMode mode) => MaterialApp(
      home: Scaffold(
        body: PowerActions(
          power: (mode: mode, error: null),
          onAction: actions.add,
        ),
      ),
    );

    await tester.pumpWidget(build(PowerMode.idle));
    await tester.tap(find.byTooltip('Suspend'));
    await tester.tap(find.byTooltip('Reboot'));
    await tester.tap(find.byTooltip('Power off'));
    expect(actions, [
      PowerAction.suspend,
      PowerAction.reboot,
      PowerAction.powerOff,
    ]);

    await tester.pumpWidget(build(PowerMode.executing));
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.onPressed, isNull);
    }
  });

  testWidgets('minute clock releases its pending timer on disposal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MinuteClockBuilder(
          builder: (_, now) => Text(formatClockTime(now)),
        ),
      ),
    );
    expect(find.text(formatClockTime(DateTime.now())), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
    expect(tester.takeException(), isNull);
  });
}
