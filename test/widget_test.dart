import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mozais_greeter/main.dart';

void main() {
  testWidgets('starts dormant and reveals controls on wake', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose account'), findsNothing);

    await _wake(tester);

    expect(find.byTooltip('Choose account'), findsOneWidget);
    expect(find.byTooltip('Choose a session'), findsOneWidget);
    expect(find.text('Enter Password'), findsOneWidget);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });

  testWidgets('escape returns to the dormant background', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await _wake(tester);
    expect(find.byTooltip('Choose account'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose account'), findsNothing);
  });

  testWidgets('shows a digital clock only while dormant', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    final clock = find.textContaining(RegExp(r'^\d{2}:\d{2}$'));
    expect(clock, findsOneWidget);

    await _wake(tester);
    expect(clock, findsNothing);
  });

  testWidgets('mouse click wakes the greeter', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose account'), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose account'), findsOneWidget);
  });

  testWidgets('enter begins authentication once a session is ready', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await _wake(tester);

    await tester.tap(find.byTooltip('Choose account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isTrue);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('selects account and session before starting authentication', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await _wake(tester);

    await tester.tap(find.byTooltip('Choose account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Choose a session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sway'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isTrue);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('submits a response and starts the selected session', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await _wake(tester);

    await tester.tap(find.byTooltip('Choose account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Choose a session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sway'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.text('Starting session...'), findsOneWidget);
  });

  testWidgets('power actions remain independently reachable', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Suspend'), findsOneWidget);
    expect(find.byTooltip('Reboot'), findsOneWidget);
    expect(find.byTooltip('Power off'), findsOneWidget);

    await tester.tap(find.byTooltip('Power off'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _wake(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  await tester.pumpAndSettle();
}
