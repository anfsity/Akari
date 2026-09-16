import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mozais_greeter/main.dart';

void main() {
  testWidgets('renders the initial account selection scene', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Choose account'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('can go back and choose a different account', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(
      find.text('Continue to receive the authentication prompt.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Choose account'), findsOneWidget);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    expect(
      find.text('Continue to receive the authentication prompt.'),
      findsOneWidget,
    );
  });

  testWidgets('shows one password field only after the backend prompt', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Password'), findsAtLeastNWidgets(1));
  });
}
