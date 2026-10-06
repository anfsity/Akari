import 'dart:async';

import 'package:flutter/material.dart';
import 'package:greeter_components/greeter_components.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'terrace_visuals.dart';

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
        'terracePortal' => const TerracePortal(),
        'terraceLabel' => _TerraceLabel(
          text: node.properties['text']!,
          large: node.properties['variant'] == 'large',
        ),
        'terraceAccount' => SceneRegion<AccountPickerSlots>(
          valueListenable: theme.host.accountPickerSlots,
          builder: (context, account) => _TerraceAccount(
            account: account,
            onSelect: theme.host.onSelectUser,
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
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
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
          fontSize: large ? 52 : 11,
          fontWeight: large ? FontWeight.w300 : FontWeight.w500,
          letterSpacing: large ? -1.5 : 2.6,
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
          fontWeight: FontWeight.w100,
          letterSpacing: -6,
          height: 1,
          color: Color(0xffeefaff),
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

/// An anchored account marker opens choices at the same point in the scene,
/// preserving spatial context and native menu keyboard navigation.
class _TerraceAccount extends StatelessWidget {
  const _TerraceAccount({required this.account, required this.onSelect});

  final AccountPickerSlots account;
  final ValueChanged<UserSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return PopupMenuButton<UserSummary>(
      tooltip: 'Choose account',
      enabled: account.canSelect,
      position: PopupMenuPosition.under,
      popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            ),
      color: const Color(0xff102e43),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: accent.withValues(alpha: 0.3)),
      ),
      itemBuilder: (context) => [
        for (final user in account.users)
          PopupMenuItem<UserSummary>(
            value: user,
            onTap: () => onSelect(user),
            child: Row(
              children: [
                Icon(
                  account.selected?.id == user.id
                      ? Icons.check
                      : Icons.person_outline,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(user.displayName)),
              ],
            ),
          ),
      ],
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xb3102e43),
              border: Border.all(color: accent.withValues(alpha: 0.6)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.12),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Icon(Icons.person_outline, color: accent, size: 24),
          ),
        ),
      ),
    );
  }
}
