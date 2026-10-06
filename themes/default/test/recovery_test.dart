import 'package:flutter/material.dart';
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

    gateway.serviceUnavailable = false;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(gateway.stateCalls, 2);
    expect(feature.state.serviceMode, ServiceMode.ready);
    expect(feature.state.authMode, AuthMode.userSelection);
    await tester.tap(find.byTooltip('Choose account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });
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

  @override
  Future<BackendStateSnapshot> getState() async {
    stateCalls++;
    if (serviceUnavailable) {
      throw const GreeterGatewayException('Service disconnected');
    }
    return super.getState();
  }
}
