import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_studio/src/studio_form.dart';

Future<void> _pumpSliderField(WidgetTester tester, List<double> commits) async {
  var value = 12.34;
  await tester.pumpWidget(
    ShadcnApp(
      home: Scaffold(
        child: Center(
          child: SizedBox(
            width: 320,
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StudioSliderField(
                    sliderKey: const ValueKey('slider'),
                    label: 'Radius',
                    value: value,
                    maximum: 100,
                    onPreview: (_) {},
                    onCommit: (next) {
                      commits.add(next);
                      setState(() => value = next);
                    },
                    onCancel: () {},
                  ),
                  const TextField(key: ValueKey('outside')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('focusing a rounded readout does not edit the value', (
    tester,
  ) async {
    final commits = <double>[];
    await _pumpSliderField(tester, commits);
    expect(find.text('12.3'), findsOneWidget);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('outside')));
    await tester.pumpAndSettle();

    expect(commits, isEmpty);
  });

  testWidgets('submitting precise text and then blurring commits once', (
    tester,
  ) async {
    final commits = <double>[];
    await _pumpSliderField(tester, commits);

    await tester.enterText(find.byType(TextField).first, '23.456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('outside')));
    await tester.pumpAndSettle();

    expect(commits, [23.456]);
    expect(find.text('23.5'), findsOneWidget);
  });

  testWidgets('text edits reject invalid numbers and clamp on blur', (
    tester,
  ) async {
    final commits = <double>[];
    await _pumpSliderField(tester, commits);

    for (final text in ['invalid', 'NaN', 'Infinity']) {
      await tester.enterText(find.byType(TextField).first, text);
      await tester.tap(find.byKey(const ValueKey('outside')));
      await tester.pumpAndSettle();
      expect(commits, isEmpty);
      expect(find.text('12.3'), findsOneWidget);
    }

    await tester.enterText(find.byType(TextField).first, '200');
    await tester.tap(find.byKey(const ValueKey('outside')));
    await tester.pumpAndSettle();
    expect(commits, [100]);
    expect(find.text('100.0'), findsOneWidget);
  });
}
