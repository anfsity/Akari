import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter_ui/feature/greeter_feature.dart';
import 'package:greeter_ui/feature/greeter_state.dart';
import 'package:greeter_ui/feature/ports/greeter_gateway.dart';
import 'package:greeter_ui/scene/greeter_scene_adapter.dart';
import 'package:theme_default/theme.dart';

void main() {
  testWidgets('reconnects an unavailable service from the retry button', (
    tester,
  ) async {
    final gateway = _RecoveryGateway()..serviceUnavailable = true;
    final feature = await _mountGreeter(tester, gateway);
    expect(feature.state.serviceMode, ServiceMode.unavailable);
    expect(find.text('Service disconnected'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(feature.state.dormant, isFalse);
    expect(find.byIcon(Icons.refresh).hitTestable(), findsOneWidget);

    gateway.serviceUnavailable = false;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(gateway.stateCalls, 2);
    expect(feature.state.serviceMode, ServiceMode.ready);
    expect(feature.state.authMode, AuthMode.userSelection);
    await _selectAccount(tester, 'Alice');
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches account and clears the previous credential', (
    tester,
  ) async {
    final gateway = _RecoveryGateway();
    final feature = await _mountGreeter(tester, gateway);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await _selectAccount(tester, 'Alice');
    await tester.enterText(find.byType(TextField), 'alice-secret');

    await _selectAccount(tester, 'Bob');

    expect(gateway.cancelCalls, 1);
    expect(feature.state.selectedUser?.id, 'bob');
    expect(feature.state.authMode, AuthMode.prompting);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), 'bob-secret');
    await _selectAccount(tester, 'Bob');
    expect(gateway.cancelCalls, 1);
    expect(field.controller!.text, 'bob-secret');
    expect(tester.takeException(), isNull);
  });

  for (final useKeyboard in [false, true]) {
    testWidgets(
      'retries session launch using ${useKeyboard ? 'Enter' : 'the arrow'}',
      (tester) async {
        final gateway = _RecoveryGateway()..sessionUnavailable = true;
        final feature = await _mountGreeter(tester, gateway);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        await _selectAccount(tester, 'Alice');
        await tester.enterText(find.byType(TextField), 'secret');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(gateway.startCalls, 1);
        expect(feature.state.authMode, AuthMode.sessionSelection);
        expect(find.byIcon(Icons.arrow_forward).hitTestable(), findsOneWidget);

        await tester.tap(find.byTooltip('Choose a session'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sway'));
        await tester.pumpAndSettle();
        final sessionStart = Completer<void>();
        gateway.sessionUnavailable = false;
        gateway.sessionStartFuture = sessionStart.future;
        if (useKeyboard) {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.byIcon(Icons.arrow_forward));
        }
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(gateway.startCalls, 2);
        expect(gateway.startedSessionId, 'wayland:sway');
        expect(feature.state.authMode, AuthMode.submitting);

        sessionStart.complete();
        await tester.pumpAndSettle();
        expect(feature.state.authMode, AuthMode.handingOff);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _selectAccount(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('Choose account'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<GreeterFeature> _mountGreeter(
  WidgetTester tester,
  _RecoveryGateway gateway,
) async {
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
  return feature;
}

class _RecoveryGateway extends DemoGreeterGateway {
  bool serviceUnavailable = false;
  int stateCalls = 0;
  int cancelCalls = 0;
  bool sessionUnavailable = false;
  int startCalls = 0;
  String? startedSessionId;
  Future<void>? sessionStartFuture;

  @override
  Future<BackendStateSnapshot> getState() async {
    stateCalls++;
    if (serviceUnavailable) {
      throw const GreeterGatewayException('Service disconnected');
    }
    return super.getState();
  }

  @override
  Future<void> cancel(String attemptId) async {
    cancelCalls++;
    await super.cancel(attemptId);
  }

  @override
  Future<void> startSession(String attemptId, String sessionId) async {
    startCalls++;
    startedSessionId = sessionId;
    if (sessionUnavailable) {
      throw const GreeterGatewayException('Session cannot start');
    }
    await sessionStartFuture;
    await super.startSession(attemptId, sessionId);
  }
}
