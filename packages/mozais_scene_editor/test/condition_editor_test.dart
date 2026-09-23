import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_scene_editor/src/condition_editor.dart';
import 'package:mozais_scene_editor/src/editor_strings.dart';
import 'package:mozais_scene_editor/src/english_strings.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required SceneCondition? condition,
    required ValueChanged<SceneCondition?> onChanged,
  }) {
    return tester.pumpWidget(
      EditorStringsScope(
        strings: const EnglishStrings(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConditionEditor(
                condition: condition,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a preset replaces the condition', (tester) async {
    SceneCondition? result;
    await pump(
      tester,
      condition: const ScenePredicateCondition(ScenePredicate.isAuthError),
      onChanged: (value) => result = value,
    );

    await tester.tap(find.text('asleep'));
    await tester.pump();

    expect(result, isA<ScenePredicateCondition>());
    expect(
      (result! as ScenePredicateCondition).predicate,
      ScenePredicate.isDormant,
    );
  });

  testWidgets('shows human predicate labels', (tester) async {
    await pump(
      tester,
      condition: const ScenePredicateCondition(ScenePredicate.isAuthPrompting),
      onChanged: (_) {},
    );

    expect(find.text('prompting for credentials'), findsOneWidget);
  });

  testWidgets('nested conditions appear under Advanced', (tester) async {
    const condition = SceneAll([
      SceneAny([ScenePredicateCondition(ScenePredicate.isDormant)]),
    ]);
    await pump(tester, condition: condition, onChanged: (_) {});

    expect(find.text('Advanced'), findsOneWidget);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();

    expect(
      find.text('Nested condition. Edit it in the JSON file.'),
      findsOneWidget,
    );
  });

  testWidgets('choosing Always clears the condition', (tester) async {
    SceneCondition? result = const ScenePredicateCondition(
      ScenePredicate.isDormant,
    );
    await pump(
      tester,
      condition: const ScenePredicateCondition(ScenePredicate.isDormant),
      onChanged: (value) => result = value,
    );

    await tester.tap(find.text('Always'));
    await tester.pump();

    expect(result, isNull);
  });
}
