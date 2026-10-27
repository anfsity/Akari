import 'package:flutter_test/flutter_test.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/studio_preview_host.dart';

void main() {
  test(
    'scenarios project coherent runtime state and retain borrowed resources',
    () {
      final simulation = StudioPreviewHost();
      addTearDown(simulation.dispose);
      final host = simulation.host;
      final credential = host.credentialController;
      final focus = host.credentialFocusNode;
      final authSlots = host.authPromptSlots;
      for (final entry in {
        StudioPreviewScenario.password: (AuthMode.prompting, ServiceMode.ready),
        StudioPreviewScenario.username: (AuthMode.prompting, ServiceMode.ready),
        StudioPreviewScenario.submitting: (
          AuthMode.submitting,
          ServiceMode.ready,
        ),
        StudioPreviewScenario.rejectedPassword: (
          AuthMode.prompting,
          ServiceMode.ready,
        ),
        StudioPreviewScenario.error: (AuthMode.error, ServiceMode.ready),
        StudioPreviewScenario.userSelection: (
          AuthMode.userSelection,
          ServiceMode.ready,
        ),
        StudioPreviewScenario.sessionSelection: (
          AuthMode.sessionSelection,
          ServiceMode.ready,
        ),
        StudioPreviewScenario.starting: (
          AuthMode.userSelection,
          ServiceMode.starting,
        ),
        StudioPreviewScenario.unavailable: (
          AuthMode.userSelection,
          ServiceMode.unavailable,
        ),
      }.entries) {
        credential.text = 'preview only';
        simulation.updateScenario(entry.key);
        expect(host.authPromptSlots.value.mode, entry.value.$1);
        expect(host.serviceSlots.value.mode, entry.value.$2);
        expect(
          host.accountPickerSlots.value.selected,
          host.authPromptSlots.value.selectedUser,
        );
        expect(host.accountPickerSlots.value.users, hasLength(2));
        expect(host.sessionPickerSlots.value.sessions, hasLength(2));
        expect(host.credentialController, same(credential));
        expect(host.credentialFocusNode, same(focus));
        expect(host.authPromptSlots, same(authSlots));
        expect(credential.text, isEmpty);
      }
      simulation.updateScenario(StudioPreviewScenario.username);
      expect(authSlots.value.prompt, (
        kind: PromptKind.visible,
        text: 'Username',
      ));
      expect(authSlots.value.selectedUser, isNull);
      simulation.updateScenario(StudioPreviewScenario.rejectedPassword);
      expect(authSlots.value.promptError, isNotEmpty);
      simulation.updateScenario(StudioPreviewScenario.error);
      expect(
        authSlots.value.error!.recovery,
        GreeterRecovery.retryAuthentication,
      );
      simulation.updateScenario(StudioPreviewScenario.unavailable);
      expect(
        host.serviceSlots.value.error!.recovery,
        GreeterRecovery.reconnectService,
      );
    },
  );
}
