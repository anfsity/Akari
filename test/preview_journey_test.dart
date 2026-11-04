import 'package:flutter_test/flutter_test.dart';
import 'package:theme_default/theme.dart';

import '../tool/preview/journey.dart';
import 'package:akari_cli/akari_cli.dart' show previewScenarioNames;

void main() {
  testWidgets(
    'preview scenarios release authentication state between journeys',
    (tester) async {
      for (final scenario in previewScenarioNames) {
        await runPreviewScenario(tester, buildDefaultTheme, scenario);
      }
    },
  );
}
