import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter/app/app.dart';
import 'package:greeter_ui/greeter_ui.dart';
import 'package:theme_default/theme.dart';

void main() {
  final binding = _DisplayBinding();

  testWidgets(
    'displays share login state, credentials, and one keyboard action',
    (tester) async {
      final dispatcher = binding.platformDispatcher;
      await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
      await tester.pumpAndSettle();
      final originalAdapter = tester.widget<GreeterSceneAdapter>(
        find.byType(GreeterSceneAdapter),
      );
      final feature = originalAdapter.feature;

      final secondary = TestFlutterView(
        view: _SecondaryView(tester.view),
        platformDispatcher: dispatcher,
        display: tester.view.display,
      );
      dispatcher.connectView(secondary);
      await tester.pumpAndSettle();
      final adapters = tester
          .widgetList<GreeterSceneAdapter>(find.byType(GreeterSceneAdapter))
          .toList();
      expect(adapters, hasLength(2));
      expect(
        adapters.every((adapter) => identical(adapter.feature, feature)),
        isTrue,
      );
      expect(
        adapters.every(
          (adapter) => identical(
            adapter.credentialController,
            originalAdapter.credentialController,
          ),
        ),
        isTrue,
      );
      expect(adapters.where((adapter) => adapter.isActive), hasLength(1));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      // Feature commands are shared, so both screens leave dormant together.
      expect(feature.dormantSlots.value, isFalse);
      expect(find.byTooltip('Choose account').hitTestable(), findsNWidgets(2));
      await tester.tap(find.byTooltip('Choose account').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice').last);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_forward).hitTestable(), findsNWidgets(2));
      final fields = find.byType(TextField);
      await tester.enterText(fields.first, 'secret');
      expect(
        tester
            .widgetList<TextField>(fields)
            .map((field) => field.controller!.text),
        everyElement('secret'),
      );

      await binding.defaultBinaryMessenger.handlePlatformMessage(
        'akari/displays',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('focusView', secondary.viewId),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields.last).focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(feature.dormantSlots.value, isTrue);
      expect(originalAdapter.credentialController!.text, isEmpty);
      expect(find.byIcon(Icons.arrow_forward).hitTestable(), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();
      expect(originalAdapter.credentialController!.text, 'a');

      dispatcher.disconnectView();
      await tester.pumpAndSettle();
      final remaining = tester.widget<GreeterSceneAdapter>(
        find.byType(GreeterSceneAdapter),
      );
      expect(remaining.feature, same(feature));
      expect(remaining.isActive, isTrue);
      expect(feature.authPromptSlots.value.mode, AuthMode.prompting);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      expect(originalAdapter.credentialController!.text, 'a');

      dispatcher.connectView(secondary);
      await tester.pumpAndSettle();
      expect(find.byType(GreeterSceneAdapter), findsNWidgets(2));
      expect(tester.widget<TextField>(fields.last).controller!.text, 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      // A second adapter processing Enter would submit an empty response and
      // overwrite the successful handoff with another authentication transition.
      expect(feature.authPromptSlots.value.mode, AuthMode.handingOff);
      expect(find.text('Starting session...'), findsNWidgets(2));

      dispatcher.disconnectView();
      await tester.pumpAndSettle();
      expect(find.byType(GreeterSceneAdapter), findsOneWidget);
      expect(
        tester
            .widget<GreeterSceneAdapter>(find.byType(GreeterSceneAdapter))
            .feature,
        same(feature),
      );
      expect(feature.authPromptSlots.value.mode, AuthMode.handingOff);
      expect(tester.takeException(), isNull);
    },
  );
}

class _DisplayBinding extends AutomatedTestWidgetsFlutterBinding {
  late final _DisplayDispatcher _dispatcher = _DisplayDispatcher(
    platformDispatcher: ui.PlatformDispatcher.instance,
  );

  @override
  _DisplayDispatcher get platformDispatcher => _dispatcher;
}

class _DisplayDispatcher extends TestPlatformDispatcher {
  _DisplayDispatcher({required super.platformDispatcher});

  TestFlutterView? _secondary;

  @override
  Iterable<TestFlutterView> get views => [...super.views, ?_secondary];

  void connectView(TestFlutterView view) {
    _secondary = view;
    onMetricsChanged!();
  }

  void disconnectView() {
    _secondary = null;
    onMetricsChanged!();
  }
}

// A second surface with its own size and scale; rendering stays in the test
// pipeline rather than forwarding this view's scene to the implicit surface.
class _SecondaryView extends Fake implements ui.FlutterView {
  _SecondaryView(this.primary);
  final TestFlutterView primary;

  @override
  int get viewId => 42;
  @override
  ui.PlatformDispatcher get platformDispatcher => primary.platformDispatcher;
  @override
  ui.Display get display => primary.display;
  @override
  double get devicePixelRatio => 2;
  @override
  ui.Size get physicalSize => const ui.Size(2560, 1440);
  @override
  ui.ViewConstraints get physicalConstraints =>
      ui.ViewConstraints.tight(physicalSize);
  @override
  ui.ViewPadding get padding => FakeViewPadding.zero;
  @override
  ui.ViewPadding get viewPadding => FakeViewPadding.zero;
  @override
  ui.ViewPadding get viewInsets => FakeViewPadding.zero;
  @override
  ui.ViewPadding get systemGestureInsets => FakeViewPadding.zero;
  @override
  ui.GestureSettings get gestureSettings => const ui.GestureSettings();
  @override
  List<ui.DisplayFeature> get displayFeatures => const [];
  @override
  ui.DisplayCornerRadii? get displayCornerRadii => null;
  @override
  void render(ui.Scene scene, {ui.Size? size}) {}
  @override
  void updateSemantics(ui.SemanticsUpdate update) {}
}
