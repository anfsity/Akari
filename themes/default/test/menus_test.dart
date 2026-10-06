import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_default/terrace_menus.dart';
import 'package:theme_default/theme.dart';
import 'package:theme_sdk/theme_sdk.dart';

void main() {
  testWidgets('arrow keys and Enter select without submitting a credential', (
    tester,
  ) async {
    SessionSummary? selected;
    await tester.pumpWidget(_getApp(onSelect: (value) => selected = value));
    await tester.tap(find.byTooltip('Choose a session'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, (id: 'session-0', name: 'Desktop 0'));
    expect(find.byType(PopupMenuItem<SessionSummary>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'menu fits a small viewport and scrolls with reduced motion $reduced',
      (tester) async {
        tester.view.physicalSize = const Size(320, 300);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SessionSummary? selected;
        await tester.pumpWidget(
          _getApp(
            onSelect: (value) => selected = value,
            count: 30,
            reduced: reduced,
          ),
        );
        await tester.tap(find.byTooltip('Choose a session'));
        await tester.pumpAndSettle();
        final scroll = find.byType(SingleChildScrollView);
        final rect = tester.getRect(scroll);
        expect(rect.left, greaterThanOrEqualTo(8));
        expect(rect.right, lessThanOrEqualTo(312));
        expect(rect.top, greaterThanOrEqualTo(8));
        expect(rect.bottom, lessThanOrEqualTo(292));
        final last = find.text('Desktop 29');
        await tester.ensureVisible(last);
        await tester.pumpAndSettle();
        await tester.tap(last);
        await tester.pumpAndSettle();
        expect(selected?.id, 'session-29');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('outside dismissal restores the selector and its focus', (
    tester,
  ) async {
    await tester.pumpWidget(_getApp(onSelect: (_) {}));
    await tester.tap(find.byTooltip('Choose a session'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<SessionSummary>), findsNothing);
    expect(find.byTooltip('Choose a session').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Choose a session'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<SessionSummary>), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

Widget _getApp({
  required ValueChanged<SessionSummary> onSelect,
  int count = 2,
  bool reduced = false,
}) => MaterialApp(
  theme: buildDefaultTheme().materialTheme,
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: reduced,
      textScaler: const TextScaler.linear(1.5),
    ),
    child: Scaffold(
      body: Align(
        alignment: Alignment.bottomRight,
        child: SizedBox(
          width: 240,
          height: 60,
          child: TerraceSessionPicker(
            session: SessionPickerSlots(
              mode: CatalogMode.ready,
              sessions: [
                for (var index = 0; index < count; index++)
                  (id: 'session-$index', name: 'Desktop $index'),
              ],
              selected: null,
              error: null,
            ),
            onSelect: onSelect,
            onRetry: () {},
          ),
        ),
      ),
    ),
  ),
);
