import 'package:flutter/material.dart';
import 'package:greeter_components/greeter_components.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'terrace_menus.dart';
import 'terrace_visuals.dart';

const _contentScale = 1.3;

/// Scene-specific presentation, borrowing the standard authentication controls
/// so prompt, recovery and session semantics retain one authoritative path.
class TerraceComponents implements GreeterThemeComponents {
  TerraceComponents(this.theme)
    : _controls = StandardGreeterComponents(theme, textAlign: TextAlign.start);

  final GreeterThemeContext theme;
  final StandardGreeterComponents _controls;

  @override
  Widget build(BuildContext context, SceneNode node) {
    final component = switch (node.componentId) {
      'terraceClock' => const _TerraceClock(),
      'terraceLabel' => _TerraceLabel(
        text: node.properties['text']!,
        large: node.properties['variant'] == 'large',
      ),
      'terraceAccount' => SceneRegion<AccountPickerSlots>(
        valueListenable: theme.host.accountPickerSlots,
        builder: (context, account) => TerraceAccountPicker(
          account: account,
          onSelect: theme.host.onSelectUser,
        ),
      ),
      'sessionPicker' => SceneRegion<SessionPickerSlots>(
        valueListenable: theme.host.sessionPickerSlots,
        builder: (context, session) => TerraceSessionPicker(
          session: session,
          onSelect: theme.host.onSelectSession,
          onRetry: theme.host.onRetrySessionCatalog,
        ),
      ),
      'credentialField' => SceneRegion<AuthPromptSlots>(
        valueListenable: theme.host.authPromptSlots,
        builder: (context, auth) => TerraceCredentialFeedback(
          auth: auth,
          child: CredentialField(
            auth: auth,
            controller: theme.host.credentialController,
            focusNode: theme.host.credentialFocusNode,
            textAlign: _controls.textAlign,
          ),
        ),
      ),
      'primaryAction' => ListenableBuilder(
        listenable: Listenable.merge([
          theme.host.serviceSlots,
          theme.host.authPromptSlots,
        ]),
        builder: (context, _) => PrimaryAction(
          service: theme.host.serviceSlots.value,
          auth: theme.host.authPromptSlots.value,
          filled: false,
          onRespond: theme.host.onRespondToPrompt,
          onStartSession: theme.host.onStartSession,
          onRetry: theme.host.onRetry,
        ),
      ),
      _ => _controls.build(context, node),
    };
    return ScaledNodeRegion(
      node: node,
      canvas: theme.canvas,
      scale: _contentScale,
      child: component,
    );
  }
}

class _TerraceLabel extends StatelessWidget {
  const _TerraceLabel({required this.text, required this.large});

  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontSize: large ? 48 : 11,
          fontWeight: large ? FontWeight.w300 : FontWeight.w500,
          letterSpacing: large ? -1.8 : 2,
          height: 1.15,
          color: Colors.white.withValues(alpha: large ? 0.96 : 0.72),
        ),
      ),
    ),
  );
}

class _TerraceClock extends StatelessWidget {
  const _TerraceClock();

  @override
  Widget build(BuildContext context) => MinuteClockBuilder(
    builder: (context, now) => Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          formatClockTime(now),
          style: const TextStyle(
            fontSize: 132,
            fontWeight: FontWeight.w300,
            letterSpacing: -6,
            height: 1,
            color: Color(0xffeefaff),
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ),
  );
}
