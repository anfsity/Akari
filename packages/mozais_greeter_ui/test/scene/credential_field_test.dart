import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_greeter_ui/mozais_greeter_ui.dart';
import 'package:mozais_scene/mozais_scene.dart';
import 'package:mozais_theme_default/theme.dart';

void main() {
  testWidgets('credential text fills its node so the prompt centers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final document = SceneDocument(
      id: 'credential-test',
      version: 1,
      canvas: const SceneCanvas(useSafeArea: false),
      background: const SceneBackground(kind: SceneBackgroundKind.solid),
      nodes: const [
        SceneNode(
          id: 'credential',
          componentId: 'credentialField',
          rect: SceneRect(x: 0.3, y: 0.5, width: 0.4, height: 0.06),
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

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.materialTheme,
        home: Scaffold(
          body: GreeterSceneAdapter(feature: feature, theme: theme),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textField = find.byType(TextField);
    final field = tester.widget<TextField>(textField);
    final fieldSurface = find
        .ancestor(of: textField, matching: find.byType(Align))
        .first;
    final inputRect = tester.getRect(textField);
    final surfaceRect = tester.getRect(fieldSurface);

    expect(field.textAlign, TextAlign.center);
    expect(field.textAlignVertical, TextAlignVertical.center);
    expect(surfaceRect.height, closeTo(64.8, 1));
    expect(inputRect.center.dx, closeTo(surfaceRect.center.dx, 0.5));
    expect(inputRect.center.dy, closeTo(surfaceRect.center.dy, 0.5));
  });
}
