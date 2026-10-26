import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter/app/app.dart';
import 'package:greeter_ui/greeter_ui.dart';
import 'package:theme_sdk/theme_sdk.dart' show ThemeBuilder;

/// Exercise the real app in one window with controlled authentication events.
/// Stage assertions decide when to advance; pauses only make motion observable.
/// Tests intercept the platform exit so the next scenario can reuse the engine.
Future<void> runPreviewScenario(
  WidgetTester tester,
  ThemeBuilder themeBuilder,
  String scenario,
) async {
  final gateway = _PreviewGateway();
  var exitRequests = 0;
  final hadTextInput = tester.testTextInput.isRegistered;
  if (!hadTextInput) tester.testTextInput.register();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') exitRequests++;
      return null;
    },
  );
  try {
    await tester.pumpWidget(
      MyApp(themeBuilder: themeBuilder, gateway: gateway),
    );
    final feature = tester
        .widget<GreeterSceneAdapter>(find.byType(GreeterSceneAdapter))
        .feature;
    await _waitFor(
      tester,
      () => feature.state.catalogMode == CatalogMode.ready,
      'login ready',
    );
    expect(feature.state.dormant, isTrue);
    await tester.pump(const Duration(milliseconds: 900));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _waitFor(
      tester,
      () => feature.state.prompt?.kind == PromptKind.info,
      'face scan',
    );
    expect(find.text('Attempting facial authentication'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pump(const Duration(milliseconds: 1800));
    // Enter during a scan must never submit an empty credential.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(gateway.responses.length, 0);

    if (scenario == 'password-fallback') {
      gateway.sendPasswordFallback();
      await _waitFor(
        tester,
        () =>
            feature.state.authMode == AuthMode.prompting &&
            find.byType(TextField).evaluate().isNotEmpty,
        'password fallback',
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isTrue);
      expect(field.obscureText, isTrue);
      expect(field.controller!.text, isEmpty);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(find.text('Face detection timeout reached'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1200));
      for (final character in 'password'.split('')) {
        tester.testTextInput.enterText('${field.controller!.text}$character');
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    } else {
      gateway.sendAuthenticated();
    }

    await _waitFor(tester, () {
      expect(feature.state.serviceError, isNull);
      expect(feature.state.authError, isNull);
      return feature.state.authMode == AuthMode.handingOff;
    }, 'session handoff');
    await tester.pump();
    expect(exitRequests, 1);
    expect(feature.state.authMode, AuthMode.handingOff);
    expect(gateway.sessions, [(_PreviewGateway._attemptId, 'wayland:sway')]);
    expect(
      gateway.responses,
      scenario == 'password-fallback'
          ? [(_PreviewGateway._attemptId, 'password')]
          : isEmpty,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    if (!hadTextInput) tester.testTextInput.unregister();
  }
  expect(gateway.closed, isTrue);
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() isReady,
  String stage,
) async {
  for (var frame = 0; frame < 100; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (isReady()) return;
  }
  fail('Preview timed out waiting for $stage.');
}

class _PreviewGateway implements GreeterGateway {
  final _events = StreamController<GreeterEvent>.broadcast();
  static const _attemptId = 'preview-alice';
  final responses = <(String, String)>[];
  final sessions = <(String, String)>[];
  bool closed = false;

  @override
  Stream<GreeterEvent> get events => _events.stream;

  @override
  Future<BackendStateSnapshot> getState() async =>
      const BackendStateSnapshot(state: BackendAuthState.idle, detail: '');

  @override
  Future<List<UserSummary>> getUsers() async => const [
    UserSummary(id: 'alice', displayName: 'Alice'),
  ];

  @override
  Future<List<SessionSummary>> getSessions() async => const [
    (id: 'wayland:sway', name: 'Sway'),
  ];

  @override
  Future<String> beginAuthentication(String username) async {
    _events.add(
      const BackendPromptReceived(
        attemptId: _attemptId,
        kind: PromptKind.info,
        text: 'Attempting facial authentication',
      ),
    );
    _events.add(
      const BackendStateChanged(
        attemptId: _attemptId,
        state: BackendAuthState.submittingResponse,
        detail: '',
      ),
    );
    return _attemptId;
  }

  void sendPasswordFallback() {
    _events.add(
      const BackendPromptReceived(
        attemptId: _attemptId,
        kind: PromptKind.error,
        text: 'Face detection timeout reached',
      ),
    );
    _events.add(
      const BackendPromptReceived(
        attemptId: _attemptId,
        kind: PromptKind.secret,
        text: 'Password',
      ),
    );
  }

  void sendAuthenticated() {
    _events.add(
      const BackendStateChanged(
        attemptId: _attemptId,
        state: BackendAuthState.authenticated,
        detail: '',
      ),
    );
  }

  @override
  Future<void> respond(String attemptId, String response) async {
    responses.add((attemptId, response));
    sendAuthenticated();
  }

  @override
  Future<void> cancel(String attemptId) async {}

  @override
  Future<void> startSession(String attemptId, String sessionId) async {
    sessions.add((attemptId, sessionId));
  }

  @override
  Future<void> requestPowerAction(PowerAction action) async {}

  @override
  Future<void> close() async {
    await _events.close();
    closed = true;
  }
}
