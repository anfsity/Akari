import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter_components/greeter_components.dart';
import 'package:greeter_ui/greeter_ui.dart';
import 'package:theme_default/theme.dart';
import 'package:theme_sdk/theme_sdk.dart';

void main() {
  testWidgets('glass panel uses an opaque Material surface', (tester) async {
    final document = SceneDocument(
      id: 'material-panel-test',
      version: 1,
      canvas: const SceneCanvas(useSafeArea: false),
      background: const SceneBackground(kind: SceneBackgroundKind.solid),
      nodes: const [
        SceneNode(
          id: 'panel',
          componentId: 'glassPanel',
          rect: SceneRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
        ),
      ],
    );
    final theme = buildDefaultTheme(document: document);
    final feature = GreeterFeature(gateway: DemoGreeterGateway());
    addTearDown(feature.dispose);
    await feature.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: GreeterSceneAdapter(feature: feature, theme: theme),
        ),
      ),
    );
    await tester.pump();

    final surfaceColor = theme.materialTheme.colorScheme.surfaceContainerHigh;
    final panel = find.byWidgetPredicate(
      (widget) =>
          widget is Material &&
          widget.color == surfaceColor &&
          widget.elevation == 3,
    );
    expect(panel, findsOneWidget);
    expect(tester.widget<Material>(panel).shape, isA<RoundedRectangleBorder>());
  });

  testWidgets('session selector uses a short popup transition', (tester) async {
    final document = SceneDocument(
      id: 'session-selector-test',
      version: 1,
      canvas: const SceneCanvas(useSafeArea: false),
      background: const SceneBackground(kind: SceneBackgroundKind.solid),
      nodes: const [
        SceneNode(
          id: 'session',
          componentId: 'sessionPicker',
          rect: SceneRect(x: 0.2, y: 0.2, width: 0.6, height: 0.1),
          visibleWhen: SceneNot(
            ScenePredicateCondition(ScenePredicate.isDormant),
          ),
        ),
      ],
    );
    final theme = ThemeDefinition(
      id: 'standard-session-test',
      document: document,
      bundle: buildDefaultTheme().bundle,
      components: StandardGreeterComponents.new,
    );
    final feature = GreeterFeature(gateway: DemoGreeterGateway());
    addTearDown(feature.dispose);
    await feature.initialize();
    await feature.dispatch(const WakeGreeterCommand());

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: GreeterSceneAdapter(feature: feature, theme: theme),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byType(PopupMenuButton<SessionSummary>);
    expect(button, findsOneWidget);
    final animationStyle = tester
        .widget<PopupMenuButton<SessionSummary>>(button)
        .popUpAnimationStyle;
    expect(animationStyle?.duration, const Duration(milliseconds: 120));
    await tester.tap(find.text('Hyprland'));
    await tester.pump();
    expect(find.text('Sway'), findsOneWidget);
  });

  testWidgets('new notices replace the current notice and queued notices', (
    tester,
  ) async {
    final gateway = _PowerFailureGateway();
    final feature = GreeterFeature(gateway: gateway);
    addTearDown(feature.dispose);
    final theme = buildDefaultTheme();
    await feature.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: GreeterSceneAdapter(feature: feature, theme: theme),
        ),
      ),
    );
    await tester.pump();

    await feature.dispatch(
      const RequestPowerActionCommand(PowerAction.powerOff),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Power warning 1'), findsOneWidget);

    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .showSnackBar(const SnackBar(content: Text('Queued notice')));
    await feature.dispatch(const RequestPowerActionCommand(PowerAction.reboot));
    await tester.pump();
    await tester.pump();

    expect(find.text('Power warning 2'), findsOneWidget);
    expect(find.text('Power warning 1'), findsNothing);
    expect(find.text('Queued notice'), findsNothing);
  });

  testWidgets(
    'typeahead buffered on one display flushes when focus moves before prompt arrives',
    (tester) async {
      final gateway = _DelayedPromptGateway();
      final feature = GreeterFeature(gateway: gateway);
      addTearDown(feature.dispose);
      final theme = buildDefaultTheme();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await feature.initialize();
      await tester.pump();
      await feature.dispatch(const WakeGreeterCommand());
      await tester.pump();
      await feature.dispatch(
        const SelectSessionCommand((id: 'wayland:sway', name: 'Sway')),
      );
      unawaited(
        feature.dispatch(
          const SelectUserCommand(UserSummary(id: 'alice', displayName: 'Alice')),
        ),
      );
      await tester.pump();

      Widget buildPair({required bool firstActive}) => MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: GreeterSceneAdapter(
                  feature: feature,
                  theme: theme,
                  credentialController: controller,
                  isActive: firstActive,
                ),
              ),
              Expanded(
                child: GreeterSceneAdapter(
                  feature: feature,
                  theme: theme,
                  credentialController: controller,
                  isActive: !firstActive,
                ),
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(buildPair(firstActive: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      expect(controller.text, isEmpty);

      await tester.pumpWidget(buildPair(firstActive: false));
      await tester.pump();
      gateway.sendPrompt();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(controller.text, 'pw');
    },
  );

  testWidgets(
    'replacing credentialController updates ownership without disposing external controller',
    (tester) async {
      final external = TextEditingController(text: 'keep');
      addTearDown(external.dispose);
      final feature = GreeterFeature(gateway: DemoGreeterGateway());
      addTearDown(feature.dispose);
      final theme = buildDefaultTheme();
      await feature.initialize();

      Widget buildAdapter(TextEditingController? controller) => MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: GreeterSceneAdapter(
            feature: feature,
            theme: theme,
            credentialController: controller,
          ),
        ),
      );

      await tester.pumpWidget(buildAdapter(null));
      await tester.pump();
      await tester.pumpWidget(buildAdapter(external));
      await tester.pump();
      await tester.pumpWidget(buildAdapter(null));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());

      // External controller must still be usable after adapter swaps and dispose.
      external.text = 'still-alive';
      expect(external.text, 'still-alive');
    },
  );
}

class _DelayedPromptGateway extends DemoGreeterGateway {
  final _controller = StreamController<GreeterEvent>.broadcast();

  @override
  Stream<GreeterEvent> get events => _controller.stream;

  @override
  Future<String> beginAuthentication(String username) async {
    _controller.add(
      const BackendStateChanged(
        attemptId: 'delayed-1',
        state: BackendAuthState.creatingSession,
        detail: '',
      ),
    );
    return 'delayed-1';
  }

  void sendPrompt() {
    _controller.add(
      const BackendPromptReceived(
        attemptId: 'delayed-1',
        kind: PromptKind.secret,
        text: 'Password',
      ),
    );
    _controller.add(
      const BackendStateChanged(
        attemptId: 'delayed-1',
        state: BackendAuthState.waitingForInput,
        detail: '',
      ),
    );
  }

  @override
  Future<void> close() => _controller.close();
}

class _PowerFailureGateway extends DemoGreeterGateway {
  var _noticeCount = 0;

  @override
  Future<void> requestPowerAction(PowerAction action) async {
    _noticeCount++;
    throw GreeterGatewayException(
      'Power warning $_noticeCount',
      kind: GreeterErrorKind.power,
    );
  }
}
