import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter_ui/feature/greeter_feature.dart';
import 'package:greeter_ui/feature/ports/greeter_gateway.dart';
import 'package:greeter_ui/scene/greeter_scene_adapter.dart';
import 'package:theme_preset1/preset_visuals.dart';
import 'package:theme_preset1/theme.dart';
import 'package:theme_sdk/theme_sdk.dart';

const _weatherFrameSize = Size(1920, 1080);

void main() {
  for (final size in [
    const Size(800, 600),
    const Size(1280, 720),
    const Size(1920, 1080),
    const Size(2467, 1580),
    const Size(2560, 1080),
  ]) {
    testWidgets('dispersed controls support login at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final feature = await _mount(tester);
      expect(find.byTooltip('Choose account').hitTestable(), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _advance(tester);
      await _select(tester, 'Choose account', 'Alice');
      await _select(tester, 'Choose a session', 'Sway');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
      expect(field.decoration!.border, InputBorder.none);
      expect(field.focusNode!.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.byIcon(Icons.arrow_forward).hitTestable());
      await _advance(tester);
      expect(feature.state.authMode, AuthMode.handingOff);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(1920, 1080), const Size(2467, 1580)]) {
    testWidgets('choice menus stay below their visible labels at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mount(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _advance(tester);
      await _select(tester, 'Choose account', 'Alice');
      for (final choice in [
        (tooltip: 'Choose account', text: 'Alice'),
        (tooltip: 'Choose a session', text: 'Hyprland'),
      ]) {
        final label = tester.getRect(find.text(choice.text));
        await tester.tap(find.byTooltip(choice.tooltip));
        await _advance(tester);
        final item = tester.getRect(
          find.byWidgetPredicate((widget) => widget is PopupMenuItem).first,
        );
        expect(item.left, lessThan(label.center.dx));
        expect(item.right, greaterThan(label.center.dx));
        expect(item.top, greaterThanOrEqualTo(label.bottom));
        expect(item.top - label.bottom, lessThan(40));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _advance(tester);
      }
    });
  }

  testWidgets('native controls keep their proportions in the Sway viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1920, 1080);
    await _mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _advance(tester);
    await _select(tester, 'Choose account', 'Alice');
    final labelHeight = tester.getRect(find.text('Alice')).height;
    final iconHeight = tester.getRect(find.byIcon(Icons.arrow_forward)).height;
    tester.view.physicalSize = const Size(2467, 1580);
    await _advance(tester);
    expect(
      tester.getRect(find.text('Alice')).height / 2467,
      closeTo(labelHeight / 1920, .0001),
    );
    expect(
      tester.getRect(find.byIcon(Icons.arrow_forward)).height / 2467,
      closeTo(iconHeight / 1920, .0001),
    );
  });

  testWidgets(
    'popup Escape, account changes and interrupted wake preserve input ownership',
    (tester) async {
      final feature = await _mount(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _advance(tester);
      await _select(tester, 'Choose account', 'Alice');
      for (final tooltip in ['Choose account', 'Choose a session']) {
        await tester.tap(find.byTooltip(tooltip));
        await _advance(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _advance(tester);
        expect(feature.state.dormant, isFalse);
      }
      await tester.enterText(find.byType(TextField), 'discard-me');
      await _select(tester, 'Choose account', 'Bob');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await _advance(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'h');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(feature.state.authMode, AuthMode.prompting);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('service and rejected credentials remain recoverable', (
    tester,
  ) async {
    final gateway = _RecoveryGateway()..unavailable = true;
    final feature = await _mount(tester, gateway: gateway);
    expect(find.text('Service disconnected'), findsOneWidget);
    gateway.unavailable = false;
    await tester.tap(find.byIcon(Icons.refresh).hitTestable());
    await _advance(tester);
    await _select(tester, 'Choose account', 'Alice');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _advance(tester);
    expect(feature.state.authMode, AuthMode.error);
    await tester.tap(find.byIcon(Icons.refresh).hitTestable());
    await _advance(tester);
    expect(feature.state.authMode, AuthMode.prompting);
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _advance(tester);
    expect(feature.state.authMode, AuthMode.handingOff);
  });

  testWidgets(
    'weather stops scheduling when reduced motion or TickerMode disables it',
    (tester) async {
      Future<void> mount({bool reduced = false, bool enabled = true}) =>
          tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: TickerMode(
                  enabled: enabled,
                  child: const PresetEnvironment(),
                ),
              ),
            ),
          );
      await mount();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await mount(reduced: true);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await mount();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
      await mount(enabled: false);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'rain visibly moves within half a second and wraps continuously',
    () async {
      final start = await _renderWeatherFrame(0);
      final falling = await _renderWeatherFrame(.5 / 120);
      final wrapped = await _renderWeatherFrame(1);
      final width = _weatherFrameSize.width.toInt();
      final height = _weatherFrameSize.height.toInt();
      var changedRainPixels = 0;
      var wrapDifference = 0;
      for (var pixel = 0; pixel < width * height; pixel++) {
        final alpha = pixel * 4 + 3;
        // This lower-right region contains weather without UI or artwork. Fine
        // rain is translucent; the changed area must exceed sparse petal edges.
        if (pixel % width >= width * .5 && pixel ~/ width >= height * .55) {
          if ((start[alpha] > 12 || falling[alpha] > 12) &&
              (start[alpha] - falling[alpha]).abs() > 7) {
            changedRainPixels++;
          }
        }
        wrapDifference += (start[alpha] - wrapped[alpha]).abs();
      }
      expect(changedRainPixels, greaterThan(500));
      expect(wrapDifference / (width * height), lessThan(.01));
    },
  );
}

Future<Uint8List> _renderWeatherFrame(double progress) async {
  final recorder = ui.PictureRecorder();
  PresetWeatherPainter(AlwaysStoppedAnimation(progress))
      .paint(Canvas(recorder), _weatherFrameSize);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _weatherFrameSize.width.toInt(),
    _weatherFrameSize.height.toInt(),
  );
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return pixels!.buffer.asUint8List();
}

// Weather intentionally never settles. Advance enough real frame boundaries
// for both async authentication events and the presence animation to complete.
Future<void> _advance(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _select(WidgetTester tester, String tooltip, String value) async {
  await tester.tap(find.byTooltip(tooltip));
  await _advance(tester);
  await tester.tap(find.text(value).last);
  await _advance(tester);
}

Future<GreeterFeature> _mount(
  WidgetTester tester, {
  DemoGreeterGateway? gateway,
}) async {
  final feature = GreeterFeature(gateway: gateway ?? DemoGreeterGateway());
  addTearDown(feature.dispose);
  await feature.initialize();
  final theme = buildPreset1Theme();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme.materialTheme,
      home: Scaffold(
        body: GreeterSceneAdapter(feature: feature, theme: theme),
      ),
    ),
  );
  await _advance(tester);
  return feature;
}

class _RecoveryGateway extends DemoGreeterGateway {
  bool unavailable = false;

  @override
  Future<BackendStateSnapshot> getState() {
    if (unavailable) {
      throw const GreeterGatewayException('Service disconnected');
    }
    return super.getState();
  }
}
