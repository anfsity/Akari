import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter_ui/greeter_ui.dart';
import 'package:theme_default/theme.dart';

void main() {
  for (final size in [
    const Size(800, 600),
    const Size(1280, 720),
    const Size(1920, 1080),
    const Size(2560, 1080),
  ]) {
    testWidgets('scan instructions and password fallback work at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final gateway = _ScanGateway();
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

      // A printable wake key must not become a hidden password when the first
      // PAM message starts a scan instead of asking for a credential.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Attempting facial authentication'), findsOneWidget);
      expect(find.text('Verifying identity...'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(gateway.respondCalls, 0);
      expect(feature.state.authError, isNull);

      gateway.emitPrompt(PromptKind.error, 'Face detection timeout reached');
      gateway.emitPrompt(PromptKind.secret, 'Password');
      await tester.pumpAndSettle();
      expect(find.text('Face detection timeout reached'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isTrue);
      expect(field.obscureText, isTrue);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.controller!.text, isEmpty);
      await tester.enterText(find.byType(TextField), 'password');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(gateway.respondCalls, 1);
      expect(gateway.startSessionCalls, 1);
      expect(feature.state.authMode, AuthMode.handingOff);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('changing account clears a scan and rejects its late success', (
    tester,
  ) async {
    final gateway = _ScanGateway()
      ..users = const [
        UserSummary(id: 'alice', displayName: 'Alice'),
        UserSummary(id: 'bob', displayName: 'Bob'),
      ];
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
    await feature.dispatch(const WakeGreeterCommand());
    await feature.dispatch(SelectUserCommand(gateway.users.first));
    await tester.pump(const Duration(seconds: 1));
    await feature.dispatch(SelectUserCommand(gateway.users.last));
    await tester.pump(const Duration(seconds: 1));
    gateway.emitAuthenticated('scan-alice');
    await tester.pump();
    expect(feature.state.selectedUser?.id, 'bob');
    expect(gateway.cancelCalls, 1);
    expect(gateway.startSessionCalls, 0);
    expect(find.text('Attempting facial authentication'), findsOneWidget);
  });
}

class _ScanGateway extends DemoGreeterGateway {
  final _scanEvents = StreamController<GreeterEvent>.broadcast();
  List<UserSummary> users = const [
    UserSummary(id: 'alice', displayName: 'Alice'),
  ];
  String _attemptId = '';
  int respondCalls = 0;
  int cancelCalls = 0;
  int startSessionCalls = 0;

  @override
  Stream<GreeterEvent> get events => _scanEvents.stream;

  @override
  Future<List<UserSummary>> listUsers() async => users;

  @override
  Future<String> beginAuthentication(String username) async {
    _attemptId = 'scan-$username';
    emitPrompt(PromptKind.info, 'Attempting facial authentication');
    _scanEvents.add(
      BackendStateChanged(
        attemptId: _attemptId,
        state: BackendAuthState.submittingResponse,
        detail: '',
      ),
    );
    return _attemptId;
  }

  void emitPrompt(PromptKind kind, String text) {
    _scanEvents.add(
      BackendPromptReceived(attemptId: _attemptId, kind: kind, text: text),
    );
  }

  void emitAuthenticated(String attemptId) {
    _scanEvents.add(
      BackendStateChanged(
        attemptId: attemptId,
        state: BackendAuthState.authenticated,
        detail: '',
      ),
    );
  }

  @override
  Future<void> respond(String attemptId, String response) async {
    respondCalls++;
    emitAuthenticated(attemptId);
  }

  @override
  Future<void> cancel(String attemptId) async {
    cancelCalls++;
  }

  @override
  Future<void> startSession(String attemptId, String sessionId) async {
    startSessionCalls++;
  }

  @override
  Future<void> close() async {
    await _scanEvents.close();
    await super.close();
  }
}
