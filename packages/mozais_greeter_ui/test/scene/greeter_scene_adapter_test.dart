import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_greeter_ui/mozais_greeter_ui.dart';
import 'package:mozais_scene/mozais_scene.dart';
import 'package:mozais_theme_default/theme.dart';

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
    final theme = buildDefaultTheme(document: document);
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
}

class _PowerFailureGateway extends DemoGreeterGateway {
  var _noticeCount = 0;

  @override
  Future<void> powerAction(PowerAction action) async {
    _noticeCount++;
    throw GreeterGatewayException(
      'Power warning $_noticeCount',
      kind: GreeterErrorKind.power,
    );
  }
}
