import 'dart:async';

import 'package:flutter/material.dart';
import 'package:greeter_components/greeter_components.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'terrace_visuals.dart';
import 'terrace_menus.dart';

/// Scene-specific presentation, borrowing the standard authentication controls
/// so prompt, recovery and session semantics retain one authoritative path.
class TerraceComponents implements GreeterThemeComponents {
  TerraceComponents(this.theme) : _controls = StandardGreeterComponents(theme);

  final GreeterThemeContext theme;
  final StandardGreeterComponents _controls;

  @override
  Widget build(BuildContext context, SceneNode node) =>
      switch (node.componentId) {
        'terraceClock' => const _TerraceClock(),
        'terracePanel' => TerracePanel(radius: theme.tokens.panelRadius),
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
            ),
          ),
        ),
        'accountName' => SceneRegion<AccountPickerSlots>(
          valueListenable: theme.host.accountPickerSlots,
          builder: (context, account) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              account.selected?.displayName ?? 'Choose account',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w400),
            ),
          ),
        ),
        _ => _controls.build(context, node),
      };
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

class _TerraceClock extends StatefulWidget {
  const _TerraceClock();

  @override
  State<_TerraceClock> createState() => _TerraceClockState();
}

class _TerraceClockState extends State<_TerraceClock> {
  late DateTime _now;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _startMinuteTimer();
  }

  void _startMinuteTimer() {
    _timer = Timer(
      Duration(milliseconds: 60000 - (_now.second * 1000 + _now.millisecond)),
      () {
        setState(() => _now = DateTime.now());
        _startMinuteTimer();
      },
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}',
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
  );
}
