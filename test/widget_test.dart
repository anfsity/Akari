import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mozais_greeter_ui/feature/greeter_feature.dart';
import 'package:mozais_greeter_ui/feature/greeter_state.dart';
import 'package:mozais_greeter_ui/feature/ports/greeter_gateway.dart';
import 'package:mozais_greeter/main.dart';
import 'package:mozais_greeter_ui/scene/greeter_scene_adapter.dart';
import 'package:mozais_theme_catalog/mozais_theme_catalog.dart';

void main() {
  testWidgets('starts dormant and reveals controls on wake', (tester) async {
    await tester.pumpWidget(const MyApp());
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
    await tester.pumpWidget(const MyApp());
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
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await _wake(tester);
    expect(find.byTooltip('Choose account'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose account').hitTestable(), findsNothing);
  });

  testWidgets('shows a digital clock only while dormant', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    final clock = find.textContaining(RegExp(r'^\d{2}:\d{2}$'));
    expect(clock, findsOneWidget);

    await _wake(tester);
    expect(clock.hitTestable(), findsNothing);
  });

  testWidgets('mouse click wakes the greeter', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose account').hitTestable(), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Choose account'), findsOneWidget);
  });

  testWidgets('selecting an account begins authentication automatically', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
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
      ThemeRegistry.resolve(ThemeRegistry.defaultThemeName)
          .materialTheme
          .colorScheme
          .primary,
    );
  });

  testWidgets('types the waking key into the password field', (tester) async {
    final feature = GreeterFeature(gateway: _SingleUserGateway());
    await feature.initialize();
    final theme = ThemeRegistry.resolve(ThemeRegistry.defaultThemeName);

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
    final theme = ThemeRegistry.resolve(ThemeRegistry.defaultThemeName);

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
    final theme = ThemeRegistry.resolve(ThemeRegistry.defaultThemeName);

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
    final theme = ThemeRegistry.resolve(ThemeRegistry.defaultThemeName);

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
    final theme = ThemeRegistry.resolve(ThemeRegistry.defaultThemeName);

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
    await tester.pumpWidget(const MyApp());
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
    await tester.pumpWidget(const MyApp());
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

/// A one-account backend so the greeter starts with every default set.
class _SingleUserGateway implements GreeterGateway {
  final StreamController<GreeterEvent> _events =
      StreamController<GreeterEvent>.broadcast();

  String? _attemptId;

  @override
  Stream<GreeterEvent> get events => _events.stream;

  @override
  Future<BackendStateSnapshot> getState() async =>
      const BackendStateSnapshot(state: BackendAuthState.idle, detail: '');

  @override
  Future<List<UserSummary>> listUsers() async => const [
    UserSummary(id: 'alice', displayName: 'Alice'),
  ];

  @override
  Future<List<SessionSummary>> listSessions() async => const [
    (id: 'wayland:hyprland', name: 'Hyprland'),
  ];

  @override
  Future<String> beginAuthentication(String username) async {
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
  Future<void> respond(String attemptId, String response) async {}

  @override
  Future<void> cancel(String attemptId) async {}

  @override
  Future<void> startSession(String attemptId, String sessionId) async {}

  @override
  Future<void> powerAction(PowerAction action) async {}

  @override
  Future<void> close() => _events.close();
}
