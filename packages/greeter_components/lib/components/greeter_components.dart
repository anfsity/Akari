import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'account_components.dart';
import 'authentication_components.dart';
import 'session_component.dart';
import 'status_component.dart';
import 'system_components.dart';

/// Optional component vocabulary shared explicitly by compiled themes.
/// Slot-backed components listen to their own content; this factory binds
/// semantic callbacks without owning authentication or rebuilding the full scene.
/// A theme using different component IDs supplies its own factory.
class StandardGreeterComponents implements GreeterThemeComponents {
  const StandardGreeterComponents(this.theme);

  final GreeterThemeContext theme;

  @override
  Widget build(BuildContext context, SceneNode node) {
    final host = theme.host;
    return switch (node.componentId) {
      'dateTime' => ThemeClock(isTime: node.properties['variant'] == 'time'),
      'powerActions' => SceneRegion<PowerSlots>(
        valueListenable: host.powerSlots,
        builder: (context, power) =>
            PowerActions(power: power, onAction: host.onRequestPowerAction),
      ),
      'glassPanel' => ThemePanel(
        tokens: theme.tokens,
        child: const SizedBox.expand(),
      ),
      'avatar' => SceneRegion<AccountPickerSlots>(
        valueListenable: host.accountPickerSlots,
        builder: (context, account) => AccountAvatar(
          account: account,
          tokens: theme.tokens,
          onSelect: host.onSelectUser,
        ),
      ),
      'accountName' => SceneRegion<AccountPickerSlots>(
        valueListenable: host.accountPickerSlots,
        builder: (context, account) => AccountName(account: account),
      ),
      'sessionPicker' => SceneRegion<SessionPickerSlots>(
        valueListenable: host.sessionPickerSlots,
        builder: (context, session) => SessionPicker(
          session: session,
          onSelect: host.onSelectSession,
          onRetry: host.onRetrySessionCatalog,
        ),
      ),
      'credentialField' => SceneRegion<AuthPromptSlots>(
        valueListenable: host.authPromptSlots,
        builder: (context, auth) => CredentialField(
          auth: auth,
          controller: host.credentialController,
          focusNode: host.credentialFocusNode,
        ),
      ),
      'primaryAction' => ListenableBuilder(
        listenable: Listenable.merge([host.serviceSlots, host.authPromptSlots]),
        builder: (context, child) => PrimaryAction(
          service: host.serviceSlots.value,
          auth: host.authPromptSlots.value,
          onRespond: host.onRespondToPrompt,
          onStartSession: host.onStartSession,
          onRetry: host.onRetry,
        ),
      ),
      'status' => ListenableBuilder(
        listenable: Listenable.merge([
          host.serviceSlots,
          host.authPromptSlots,
          host.sessionPickerSlots,
        ]),
        builder: (context, child) => GreeterStatusLine(
          service: host.serviceSlots.value,
          auth: host.authPromptSlots.value,
          session: host.sessionPickerSlots.value,
        ),
      ),
      'background' ||
      'accountPicker' ||
      'secondaryAction' ||
      'decoration' => const SizedBox.shrink(),
      _ => const SizedBox.shrink(),
    };
  }
}
