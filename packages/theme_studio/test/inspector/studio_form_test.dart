import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_studio/src/inspector/studio_form.dart';

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

  testWidgets('disclosure headers support Tab, Enter and Space', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ShadcnApp(
        home: Scaffold(
          child: Center(
            child: SizedBox(
              width: 320,
              child: StudioDisclosureSection(
                title: 'Advanced',
                child: Text('Details'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsNothing);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
  });

  testWidgets('disclosures animate without rebuilding their editors', (
    tester,
  ) async {
    var builds = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    const section = ValueKey('section');
    const field = ValueKey('disclosure-field');
    await tester.pumpWidget(
      ShadcnApp(
        home: Scaffold(
          child: Center(
            child: SizedBox(
              width: 320,
              child: StudioDisclosureSection(
                key: section,
                title: 'Advanced',
                child: Builder(
                  builder: (context) {
                    builds++;
                    return TextField(key: field, focusNode: focus);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(builds, 0);
    final closedHeight = tester.getSize(find.byKey(section)).height;

    await tester.tap(find.text('Advanced'));
    await tester.pump();
    final bodySize = tester.getSize(find.byKey(field));
    await tester.pump(kDefaultDuration ~/ 2);
    final midwayHeight = tester.getSize(find.byKey(section)).height;
    expect(midwayHeight, greaterThan(closedHeight));
    expect(tester.getSize(find.byKey(field)), bodySize);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(section)).height,
      greaterThan(midwayHeight),
    );
    expect(builds, 1);

    await tester.tap(find.byKey(field));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    await tester.tap(find.text('Advanced'));
    await tester.pump();
    expect(focus.canRequestFocus, isFalse);
    await tester.pump(kDefaultDuration ~/ 2);
    expect(find.byKey(field), findsOneWidget);
    expect(
      tester.getSize(find.byKey(section)).height,
      greaterThan(closedHeight),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(field), findsNothing);
    expect(tester.getSize(find.byKey(section)).height, closedHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion finishes active disclosures and skips transitions',
    (tester) async {
      const section = ValueKey('section');
      await tester.pumpWidget(
        const ShadcnApp(
          home: Scaffold(
            child: Center(
              child: SizedBox(
                width: 320,
                child: StudioDisclosureSection(
                  key: section,
                  title: 'Advanced',
                  child: Text('Details'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final closedHeight = tester.getSize(find.byKey(section)).height;
      await tester.tap(find.text('Advanced'));
      await tester.pump();
      await tester.pump(kDefaultDuration ~/ 2);
      final midwayHeight = tester.getSize(find.byKey(section)).height;

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(section)).height,
        greaterThan(midwayHeight),
      );
      await tester.tap(find.text('Advanced'));
      await tester.pump();
      expect(find.text('Details'), findsNothing);
      expect(tester.getSize(find.byKey(section)).height, closedHeight);
      await tester.tap(find.text('Advanced'));
      await tester.pump();
      final expandedHeight = tester.getSize(find.byKey(section)).height;
      await tester.pump(kDefaultDuration);
      expect(tester.getSize(find.byKey(section)).height, expandedHeight);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disclosure geometry follows adaptive theme scaling', (
    tester,
  ) async {
    const section = ValueKey('section');
    Future<Size> getSize(double scale) async {
      await tester.pumpWidget(
        ShadcnApp(
          theme: AdaptiveScaling(scale).scale(const ThemeData()),
          home: const Scaffold(
            child: Center(
              child: SizedBox(
                width: 320,
                child: StudioDisclosureSection(
                  key: section,
                  title: 'Advanced',
                  child: Text('Details'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(section));
    }

    final normal = await getSize(1);
    final enlarged = await getSize(1.5);
    expect(enlarged.height / normal.height, closeTo(1.5, .03));
    expect(tester.takeException(), isNull);
  });
}
