import 'package:flutter_test/flutter_test.dart';
import 'package:theme_default/theme.dart';
import 'package:greeter/app/app.dart';
import 'package:greeter_harness/greeter_harness.dart';

void main() {
  testWidgets(
    'preview scenarios release authentication state between journeys',
    (tester) async {
      for (final scenario in previewScenarioNames) {
        await runPreviewScenario(
          tester,
          (gateway) => MyApp(themeBuilder: buildDefaultTheme, gateway: gateway),
          scenario,
        );
      }
    },
  );
}
