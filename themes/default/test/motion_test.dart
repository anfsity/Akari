import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greeter_components/greeter_components.dart';
import 'package:theme_default/terrace_visuals.dart';
import 'package:theme_default/theme.dart';
import 'package:theme_sdk/theme_sdk.dart';

const _prompt = (
  mode: AuthMode.prompting,
  selectedUser: null,
  prompt: (kind: PromptKind.secret, text: 'Password'),
  error: null,
  promptError: null,
);

void main() {
  for (final kind in [
    GreeterErrorKind.authentication,
    GreeterErrorKind.input,
  ]) {
    testWidgets('$kind feedback settles and retains the input element', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      Future<void> update(AuthPromptSlots auth) =>
          tester.pumpWidget(_getApp(auth, controller, focus));
      await update(_prompt);
      await tester.pumpAndSettle();
      final input = tester.element(find.byType(TextField));
      final origin = tester.getCenter(find.byType(TextField));
      final rejected = (
        mode: AuthMode.error,
        selectedUser: null,
        prompt: null,
        error: (
          kind: kind,
          message: 'Try again',
          recovery: GreeterRecovery.retryAuthentication,
        ),
        promptError: null,
      );
      await update(rejected);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getCenter(find.byType(TextField)), isNot(origin));
      expect(tester.element(find.byType(TextField)), same(input));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byType(TextField)), origin);
      // Rebuild the same error: a slot refresh must not replay a rejection.
      await update(rejected);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getCenter(find.byType(TextField)), origin);
      // The same failure on a fresh attempt must produce feedback again.
      await update(_prompt);
      await tester.pumpAndSettle();
      await update(rejected);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getCenter(find.byType(TextField)), isNot(origin));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final reduced in [false, true]) {
    testWidgets('PAM prompt feedback respects reduced motion: $reduced', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _getApp(_prompt, controller, focus, reduced: reduced),
      );
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pump();
      final input = tester.element(find.byType(TextField));
      final origin = tester.getCenter(find.byType(TextField));
      await tester.pumpWidget(
        _getApp(
          (
            mode: _prompt.mode,
            selectedUser: null,
            prompt: _prompt.prompt,
            error: null,
            promptError: 'Incorrect password',
          ),
          controller,
          focus,
          reduced: reduced,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester.getCenter(find.byType(TextField)),
        reduced ? origin : isNot(origin),
      );
      expect(tester.element(find.byType(TextField)), same(input));
      expect(focus.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('service errors do not shake the credential field', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(_getApp(_prompt, controller, focus));
    await tester.pumpAndSettle();
    final origin = tester.getCenter(find.byType(TextField));
    await tester.pumpWidget(
      _getApp(
        (
          mode: AuthMode.error,
          selectedUser: null,
          prompt: null,
          error: (
            kind: GreeterErrorKind.transport,
            message: 'Disconnected',
            recovery: GreeterRecovery.reconnectService,
          ),
          promptError: null,
        ),
        controller,
        focus,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getCenter(find.byType(TextField)), origin);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _getApp(
  AuthPromptSlots auth,
  TextEditingController controller,
  FocusNode focus, {
  bool reduced = false,
}) => MaterialApp(
  theme: buildDefaultTheme().materialTheme,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          height: 60,
          child: TerraceCredentialFeedback(
            auth: auth,
            child: CredentialField(
              auth: auth,
              controller: controller,
              focusNode: focus,
            ),
          ),
        ),
      ),
    ),
  ),
);
