import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter_components/greeter_components.dart';
import 'package:theme_sdk/theme_sdk.dart';

void main() {
  testWidgets('AccountPortrait falls back safely when displayName is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AccountPortrait(
                user: UserSummary(id: 'alice', displayName: ''),
                accent: Colors.blue,
                fontSize: 20,
              ),
              AccountPortrait(
                user: UserSummary(id: '', displayName: ''),
                accent: Colors.blue,
                fontSize: 20,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('A'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets(
    'CredentialField submits via IME action and PrimaryAction exposes tooltips',
    (tester) async {
      final controller = TextEditingController(text: 'secret');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      var submitted = '';
      var responded = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 280,
                  height: 48,
                  child: CredentialField(
                    auth: (
                      mode: AuthMode.prompting,
                      selectedUser: null,
                      prompt: (kind: PromptKind.secret, text: 'Password'),
                      error: null,
                      promptError: null,
                    ),
                    controller: controller,
                    focusNode: focusNode,
                    onSubmitted: (value) => submitted = value,
                  ),
                ),
                SizedBox(
                  width: 56,
                  height: 56,
                  child: PrimaryAction(
                    service: (mode: ServiceMode.ready, error: null),
                    auth: (
                      mode: AuthMode.prompting,
                      selectedUser: null,
                      prompt: null,
                      error: null,
                      promptError: null,
                    ),
                    onRespond: () => responded++,
                    onStartSession: () {},
                    onRetry: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, 'secret');

      await tester.tap(find.byTooltip('Submit response'));
      expect(responded, 1);
    },
  );

  testWidgets(
    'CredentialField scan indicator pauses when TickerMode is disabled',
    (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      Widget build(bool tickerEnabled) => MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: tickerEnabled,
            child: CredentialField(
              auth: (
                mode: AuthMode.submitting,
                selectedUser: null,
                prompt: (kind: PromptKind.info, text: 'Verifying identity...'),
                error: null,
                promptError: null,
              ),
              controller: controller,
              focusNode: focusNode,
            ),
          ),
        ),
      );

      await tester.pumpWidget(build(true));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(build(false));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    },
  );
}
