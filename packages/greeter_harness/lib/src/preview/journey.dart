import 'dart:async';

import 'package:akari_cli/akari_cli.dart' show previewScenarioNames;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter_ui/greeter_ui.dart';

/// Exercise the real app in one window with controlled authentication events.
/// Stage assertions decide when to advance; pauses only make motion observable.
/// Tests intercept the platform exit so the next scenario can reuse the engine.
Future<void> runPreviewScenario(
  WidgetTester tester,
  Widget Function(GreeterGateway gateway) createApp,
  String scenario,
) async {
  if (!previewScenarioNames.contains(scenario)) {
    throw ArgumentError.value(
      scenario,
      'scenario',
      'Unsupported preview scenario. Expected one of: $previewScenarioNames.',
    );
  }
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
    await tester.pumpWidget(createApp(gateway));
    final adapters = tester
        .widgetList<GreeterSceneAdapter>(find.byType(GreeterSceneAdapter))
        .toList();
    expect(adapters, isNotEmpty);
    final activeAdapter = adapters.firstWhere(
      (adapter) => adapter.isActive,
      orElse: () => adapters.first,
    );
    final feature = activeAdapter.feature;
    final activeScope = find.byWidget(activeAdapter);
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
    expect(
      feature.state.prompt?.text,
      'Attempting facial authentication',
    );
    final textFields = find.descendant(
      of: activeScope,
      matching: find.byType(TextField),
    );
    expect(textFields, findsNothing);
    await tester.pump(const Duration(milliseconds: 1800));
    // Enter during a scan must never submit an empty credential.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(gateway.responses.length, 0);

    if (scenario == 'password-fallback') {
      gateway.sendPasswordFallback();
      await _waitFor(
        tester,
        () => feature.state.authMode == AuthMode.prompting,
        'password fallback',
      );
      expect(
        feature.state.promptError,
        'Face detection timeout reached',
      );
      if (textFields.evaluate().isNotEmpty) {
        final field = tester.widget<TextField>(textFields.first);
        expect(field.enabled, isTrue);
        expect(field.obscureText, isTrue);
        expect(field.controller!.text, isEmpty);
        expect(field.focusNode!.hasFocus, isTrue);
      }
      await tester.pump(const Duration(milliseconds: 1200));
      for (final character in 'password'.split('')) {
        tester.testTextInput.enterText(
          '${activeAdapter.credentialController?.text ?? ''}$character',
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    } else if (scenario == 'face-success') {
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
    if (textFields.evaluate().isNotEmpty) {
      expect(tester.widget<TextField>(textFields.first).enabled, isFalse);
    }
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

  void _emit(GreeterEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  @override
  Future<String> beginAuthentication(String username) async {
    _emit(
      const BackendPromptReceived(
        attemptId: _attemptId,
        kind: PromptKind.info,
        text: 'Attempting facial authentication',
      ),
    );
    _emit(
      const BackendStateChanged(
        attemptId: _attemptId,
        state: BackendAuthState.submittingResponse,
        detail: '',
      ),
    );
    return _attemptId;
  }

  void sendPasswordFallback() {
    _emit(
      const BackendPromptReceived(
        attemptId: _attemptId,
        kind: PromptKind.error,
        text: 'Face detection timeout reached',
      ),
    );
    _emit(
      const BackendPromptReceived(
        attemptId: _attemptId,
        kind: PromptKind.secret,
        text: 'Password',
      ),
    );
  }

  void sendAuthenticated() {
    _emit(
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
    _emit(
      BackendStateChanged(
        attemptId: attemptId,
        state: BackendAuthState.handingOff,
        detail: '',
      ),
    );
  }

  @override
  Future<void> requestPowerAction(PowerAction action) async {}

  @override
  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    await _events.close();
  }
}
