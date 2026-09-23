import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_greeter_ui/mozais_greeter_ui.dart';

void main() {
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
