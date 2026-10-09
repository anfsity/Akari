import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greeter_ui/feature/greeter_feature.dart';
import 'package:greeter_ui/feature/greeter_state.dart';
import 'package:greeter_ui/feature/ports/greeter_gateway.dart';

import 'package:greeter/app/app.dart';
import 'package:greeter_components/greeter_components.dart';

import 'package:theme_default/theme.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:greeter_ui/scene/greeter_scene_adapter.dart';

void main() {
  testWidgets('opening choices preserves the wallpaper pointer offset', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();
    await _wake(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(600, 100));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(const Offset(700, 140));
    await tester.pumpAndSettle();
    final motion = find.byType(TweenAnimationBuilder<Offset>);
    final offset = tester
        .widget<TweenAnimationBuilder<Offset>>(motion)
        .tween
        .end;
    expect(offset, isNot(Offset.zero));
    await tester.tap(find.byTooltip('Choose account'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TweenAnimationBuilder<Offset>>(motion).tween.end,
      offset,
    );
  });

  testWidgets('a wide account image fills the circular account marker', (
    tester,
  ) async {
    final feature = GreeterFeature(
      gateway: _SingleUserGateway(
        iconPath: File('assets/(71187447)Hello world.png').absolute.path,
      ),
    );
    addTearDown(feature.dispose);
    await feature.initialize();
    final theme = buildDefaultTheme();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: GreeterSceneAdapter(feature: feature, theme: theme),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await _wake(tester);
    final portrait = find.byType(AccountPortrait);
    final image = find.descendant(of: portrait, matching: find.byType(Image));
    final imageSize = tester.getSize(image);
    expect(imageSize, tester.getSize(portrait));
    expect(imageSize.width, imageSize.height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes each choice menu without sleeping the greeter', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();
    await _wake(tester);
    final feature = tester
        .widget<GreeterSceneAdapter>(find.byType(GreeterSceneAdapter))
        .feature;
    for (final tooltip in ['Choose account', 'Choose a session']) {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((widget) => widget is PopupMenuEntry),
        findsWidgets,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(feature.state.dormant, isFalse);
      expect(find.byTooltip(tooltip).hitTestable(), findsOneWidget);
    }
  });

  testWidgets(
    'selected account uses the backend portrait and initial fallback',
    (tester) async {
      final feature = GreeterFeature(
        gateway: _SingleUserGateway(iconPath: '/missing/avatar.png'),
      );
      addTearDown(feature.dispose);
      await feature.initialize();
      final theme = buildDefaultTheme();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.materialTheme,
          home: Scaffold(
            body: GreeterSceneAdapter(feature: feature, theme: theme),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _wake(tester);
      final portrait = tester.widget<AccountPortrait>(
        find.byType(AccountPortrait),
      );
      expect(portrait.user.iconPath, '/missing/avatar.png');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('waking retains the sharp wallpaper configuration', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();
    final wallpaper = find.byWidgetPredicate(
      (widget) => widget is Image && widget.image is AssetImage,
    );
    final image = tester.widget<Image>(wallpaper);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.widget<Image>(wallpaper), same(image));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.widget<Image>(wallpaper), same(image));
    await tester.pumpAndSettle();
  });

  for (final size in [
    const Size(800, 600),
    const Size(1280, 720),
    const Size(1920, 1080),
    const Size(2467, 1580),
    const Size(2560, 1080),
  ]) {
    testWidgets('scene controls remain usable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
      await tester.pumpAndSettle();
      await _wake(tester);
      await tester.tap(find.byTooltip('Choose account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('controls and choice menus scale with the Sway viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();
    final greetingHeight = tester.getRect(find.text('Hello World')).height;
    await _wake(tester);
    await tester.tap(find.byTooltip('Choose account'));
    await tester.pumpAndSettle();
    final menuLabelHeight = tester.getRect(find.text('Alice')).height;
    final menuRowHeight = tester
        .getRect(
          find.byWidgetPredicate((widget) => widget is PopupMenuItem).first,
        )
        .height;
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    final accountHeight = tester.getRect(find.text('Alice')).height;
    final iconHeight = tester.getRect(find.byIcon(Icons.arrow_forward)).height;
    final credentialHeight = tester.getRect(find.byType(EditableText)).height;

    tester.view.physicalSize = const Size(2467, 1580);
    await tester.pumpAndSettle();
    final scale = 2467 / 1920;
    expect(
      tester.getRect(find.text('Alice')).height,
      closeTo(accountHeight * scale, .01),
    );
    expect(
      tester.getRect(find.byIcon(Icons.arrow_forward)).height,
      closeTo(iconHeight * scale, .01),
    );
    expect(
      tester.getRect(find.byType(EditableText)).height,
      closeTo(credentialHeight * scale, .01),
    );
    for (final tooltip in ['Choose account', 'Choose a session']) {
      final anchor = tester.getRect(find.byTooltip(tooltip));
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byType(SingleChildScrollView));
      expect(menu.left, closeTo(anchor.left, .01));
      expect(menu.top, closeTo(anchor.bottom + 8, .01));
      expect(
        tester
            .getRect(
              find.byWidgetPredicate((widget) => widget is PopupMenuItem).first,
            )
            .height,
        closeTo(menuRowHeight * scale, .01),
      );
      if (tooltip == 'Choose account') {
        expect(
          tester.getRect(find.text('Alice').last).height,
          closeTo(menuLabelHeight * scale, .01),
        );
      } else {
        expect(menu.width, closeTo(anchor.width, .01));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Hello World')).height,
      closeTo(greetingHeight * scale, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wake can reverse mid-transition without losing the prompt', (
    tester,
  ) async {
    final feature = GreeterFeature(gateway: _SingleUserGateway());
    addTearDown(feature.dispose);
    await feature.initialize();
    final theme = buildDefaultTheme();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: GreeterSceneAdapter(feature: feature, theme: theme),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'h');
    expect(field.focusNode!.hasFocus, isTrue);
    expect(feature.state.authMode, AuthMode.prompting);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps the scene static on pointer movement', (
    tester,
  ) async {
    final theme = buildDefaultTheme();
    final feature = GreeterFeature(gateway: _SingleUserGateway());
    addTearDown(feature.dispose);
    await feature.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.materialTheme,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: GreeterSceneAdapter(feature: feature, theme: theme),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _wake(tester);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(const Offset(700, 100));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets(
    'hot reload refreshes theme while retaining authentication and credentials',
    (tester) async {
      var selectedSeed = Colors.red;
      ThemeDefinition buildTheme({Color? seed}) =>
          buildDefaultTheme(seed: selectedSeed);
      await tester.pumpWidget(MyApp(themeBuilder: buildTheme));
      await tester.pumpAndSettle();
      await _wake(tester);
      await tester.tap(find.byTooltip('Choose account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'secret');
      final feature = tester
          .widget<GreeterSceneAdapter>(find.byType(GreeterSceneAdapter))
          .feature;
      final oldColor = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .colorScheme
          .primary;
      selectedSeed = Colors.blue;
      unawaited(tester.binding.reassembleApplication());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .theme!
            .colorScheme
            .primary,
        isNot(oldColor),
      );
      expect(
        tester
            .widget<GreeterSceneAdapter>(find.byType(GreeterSceneAdapter))
            .feature,
        same(feature),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isTrue);
      expect(field.controller!.text, 'secret');
    },
  );

  testWidgets('starts dormant and reveals controls on wake', (tester) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose account').hitTestable(), findsNothing);

    await _wake(tester);

    expect(find.byTooltip('Choose account'), findsOneWidget);
    expect(find.byTooltip('Choose a session'), findsOneWidget);
    expect(find.text('Enter Password'), findsOneWidget);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });

  testWidgets('keeps credential field geometry stable while waking', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    final dormantSize = tester.getSize(field);
    final dormantCenter = tester.getCenter(field);

    await _wake(tester);
    await tester.pumpAndSettle();

    expect(tester.getSize(field), dormantSize);
    expect(tester.getCenter(field), dormantCenter);
  });

  testWidgets('escape returns to the dormant background', (tester) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();
    await _wake(tester);
    expect(find.byTooltip('Choose account'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose account').hitTestable(), findsNothing);
  });

  testWidgets('shows a digital clock only while dormant', (tester) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();

    final clock = find.textContaining(RegExp(r'^\d{2}:\d{2}$'));
    expect(clock, findsOneWidget);

    await _wake(tester);
    expect(clock.hitTestable(), findsNothing);
  });

  testWidgets(
    'escape and wake keep one prompt without submitting credentials',
    (tester) async {
      final gateway = _SingleUserGateway();
      final feature = GreeterFeature(gateway: gateway);
      addTearDown(feature.dispose);
      await feature.initialize();
      final theme = buildDefaultTheme();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.materialTheme,
          home: Scaffold(
            body: GreeterSceneAdapter(feature: feature, theme: theme),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _wake(tester);
      final arrow = find.byIcon(Icons.arrow_forward).hitTestable();
      expect(arrow, findsOneWidget);

      for (var cycle = 0; cycle < 5; cycle++) {
        await tester.enterText(find.byType(TextField), 'unsubmitted');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(feature.state.dormant, isTrue);
        expect(feature.state.authMode, AuthMode.prompting);
        expect(arrow, findsNothing);

        await _wake(tester);
        expect(arrow, findsOneWidget);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, isEmpty);
        expect(field.focusNode!.hasFocus, isTrue);
      }
      expect(gateway.beginCalls, 1);
      expect(gateway.cancelCalls, 0);
      expect(gateway.respondCalls, 0);
    },
  );

  testWidgets('mouse click wakes the greeter', (tester) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose account').hitTestable(), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose account'), findsOneWidget);
  });

  testWidgets('selecting an account begins authentication automatically', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();
    await _wake(tester);

    await tester.tap(find.byTooltip('Choose account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.idle();
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isTrue);
    expect(field.focusNode?.hasFocus, isTrue);

    final fieldSurface = find
        .ancestor(
          of: find.byType(TextField),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).border != null,
          ),
        )
        .first;
    final decoration =
        tester.widget<DecoratedBox>(fieldSurface).decoration as BoxDecoration;
    expect(
      (decoration.border as Border).top.color,
      buildDefaultTheme().materialTheme.colorScheme.primary,
    );
  });

  testWidgets('types the waking key into the password field', (tester) async {
    final feature = GreeterFeature(gateway: _SingleUserGateway());
    await feature.initialize();
    final theme = buildDefaultTheme();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: GreeterSceneAdapter(feature: feature, theme: theme),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isTrue);
    expect(field.focusNode?.hasFocus, isTrue);
    expect(field.controller?.text, 'h');

    feature.dispose();
  });

  testWidgets('keeps a typed credential obscured while the field exits', (
    tester,
  ) async {
    final feature = GreeterFeature(gateway: _SingleUserGateway());
    await feature.initialize();
    final theme = buildDefaultTheme();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: GreeterSceneAdapter(feature: feature, theme: theme),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.pump();

    // Escape starts the exit transition while the field still holds the
    // secret, so the field must stay obscured until it unmounts.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
    expect(field.controller?.text, isEmpty);

    feature.dispose();
  });

  testWidgets('escape works from the retry error state', (tester) async {
    final feature = GreeterFeature(gateway: _SingleUserGateway());
    await feature.initialize();
    final theme = buildDefaultTheme();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: GreeterSceneAdapter(feature: feature, theme: theme),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(feature.state.authMode, AuthMode.error);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(feature.state.dormant, isTrue);
    feature.dispose();
  });

  testWidgets('escape works when no control holds focus', (tester) async {
    final feature = GreeterFeature(gateway: _SingleUserGateway());
    await feature.initialize();
    final theme = buildDefaultTheme();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: GreeterSceneAdapter(feature: feature, theme: theme),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    // Focus can fall back to the enclosing scope while the field is disabled.
    tester.binding.focusManager.primaryFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(feature.state.dormant, isTrue);
    feature.dispose();
  });

  testWidgets('typing recovers into the prompt from the error state', (
    tester,
  ) async {
    final feature = GreeterFeature(gateway: _SingleUserGateway());
    await feature.initialize();
    final theme = buildDefaultTheme();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: GreeterSceneAdapter(feature: feature, theme: theme),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(feature.state.authMode, AuthMode.error);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();

    expect(feature.state.authMode, AuthMode.prompting);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'a');
    feature.dispose();
  });

  testWidgets('submits a response and starts the selected session', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();
    await _wake(tester);

    await tester.tap(find.byTooltip('Choose a session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sway'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Choose account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Starting session...'), findsOneWidget);
  });

  testWidgets('the confirm arrow submits the same response as enter', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();
    await _wake(tester);

    await tester.tap(find.byTooltip('Choose a session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sway'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Choose account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.text('Starting session...'), findsOneWidget);
  });

  testWidgets('the confirm arrow scales on pointer hover', (tester) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
    await tester.pumpAndSettle();
    await _wake(tester);
    await tester.tap(find.byTooltip('Choose account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.byIcon(Icons.arrow_forward)));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      1.02,
    );

    await pointer.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('power actions remain independently reachable', (tester) async {
    await tester.pumpWidget(MyApp(themeBuilder: buildDefaultTheme));
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

/// A one-account backend so the greeter starts with every default set.
class _SingleUserGateway implements GreeterGateway {
  _SingleUserGateway({this.iconPath = ''});

  final String iconPath;
  final StreamController<GreeterEvent> _events =
      StreamController<GreeterEvent>.broadcast();

  String? _attemptId;
  int beginCalls = 0;
  int cancelCalls = 0;
  int respondCalls = 0;

  @override
  Stream<GreeterEvent> get events => _events.stream;

  @override
  Future<BackendStateSnapshot> getState() async =>
      const BackendStateSnapshot(state: BackendAuthState.idle, detail: '');

  @override
  Future<List<UserSummary>> listUsers() async => [
    UserSummary(id: 'alice', displayName: 'Alice', iconPath: iconPath),
  ];

  @override
  Future<List<SessionSummary>> listSessions() async => const [
    (id: 'wayland:hyprland', name: 'Hyprland'),
  ];

  @override
  Future<String> beginAuthentication(String username) async {
    beginCalls++;
    final attemptId = 'attempt-$username';
    _attemptId = attemptId;
    scheduleMicrotask(() {
      if (_attemptId != attemptId) {
        return;
      }
      _events.add(
        BackendPromptReceived(
          attemptId: attemptId,
          kind: PromptKind.secret,
          text: 'Password',
        ),
      );
      _events.add(
        BackendStateChanged(
          attemptId: attemptId,
          state: BackendAuthState.waitingForInput,
          detail: '',
        ),
      );
    });
    return attemptId;
  }

  @override
  Future<void> respond(String attemptId, String response) async {
    respondCalls++;
  }

  @override
  Future<void> cancel(String attemptId) async {
    cancelCalls++;
  }

  @override
  Future<void> startSession(String attemptId, String sessionId) async {}

  @override
  Future<void> powerAction(PowerAction action) async {}

  @override
  Future<void> close() => _events.close();
}
