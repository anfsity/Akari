import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mozais_greeter/main.dart';

void main() {
  testWidgets('renders the initial account selection scene', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Choose account'), findsOneWidget);
    expect(find.text('Choose session'), findsOneWidget);
    expect(find.text('MOZAIS'), findsOneWidget);
    expect(find.text('Choose a session'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Sway'), findsNothing);
  });

  testWidgets('shows the power menu from the top-right control', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    final power = find.byTooltip('Power actions');
    expect(power, findsOneWidget);
    expect(tester.getTopLeft(power).dy, lessThan(100));

    await tester.tap(power);
    await tester.pumpAndSettle();
    expect(find.text('Power off'), findsOneWidget);
  });

  testWidgets('selects a session from the compact session picker', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose a session'));
    await tester.pumpAndSettle();
    expect(find.text('Sway'), findsOneWidget);
    expect(find.text('Hyprland'), findsOneWidget);

    await tester.tap(find.text('Sway'));
    await tester.pumpAndSettle();
    expect(find.text('Sway'), findsOneWidget);
    expect(find.text('Choose a session'), findsNothing);
  });

  testWidgets('can go back and choose a different account', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    expect(find.text('Choose account'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('shows one password field only after the backend prompt', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose a session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sway'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Password'), findsAtLeastNWidgets(1));
  });
}
