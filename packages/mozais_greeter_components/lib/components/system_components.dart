import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mozais_theme_sdk/mozais_theme_sdk.dart';

class ThemeClock extends StatefulWidget {
  const ThemeClock({required this.isTime, super.key});

  final bool isTime;

  @override
  State<ThemeClock> createState() => _ThemeClockState();
}

class _ThemeClockState extends State<ThemeClock> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isTime) {
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}',
            maxLines: 1,
            style: _clockStyle(context, 120, FontWeight.w300),
          ),
        ),
      );
    }
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          '${weekdays[_now.weekday - 1]}, ${months[_now.month - 1]} ${_now.day}',
          maxLines: 1,
          style: _clockStyle(context, 20, FontWeight.w500),
        ),
      ),
    );
  }
}

TextStyle _clockStyle(
  BuildContext context,
  double fontSize,
  FontWeight weight,
) {
  return TextStyle(
    color: Theme.of(context).colorScheme.primary,
    fontSize: fontSize,
    fontWeight: weight,
    height: 1.05,
    shadows: const [Shadow(color: Color(0x66000000), blurRadius: 12)],
  );
}

class PowerActions extends StatelessWidget {
  const PowerActions({required this.power, required this.onAction, super.key});

  final PowerSlots power;
  final ValueChanged<PowerAction> onAction;

  @override
  Widget build(BuildContext context) {
    final enabled = power.mode != PowerMode.executing;
    final accent = Theme.of(context).colorScheme.primary;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          _PowerIcon(
            tooltip: 'Suspend',
            icon: Icons.bedtime_outlined,
            accent: accent,
            enabled: enabled,
            onPressed: () => onAction(PowerAction.suspend),
          ),
          _PowerIcon(
            tooltip: 'Reboot',
            icon: Icons.restart_alt,
            accent: accent,
            enabled: enabled,
            onPressed: () => onAction(PowerAction.reboot),
          ),
          _PowerIcon(
            tooltip: 'Power off',
            icon: Icons.power_settings_new,
            accent: accent,
            enabled: enabled,
            onPressed: () => onAction(PowerAction.powerOff),
          ),
        ],
      ),
    );
  }
}

class _PowerIcon extends StatelessWidget {
  const _PowerIcon({
    required this.tooltip,
    required this.icon,
    required this.accent,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color accent;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
      iconSize: 22,
      color: accent,
      disabledColor: accent.withValues(alpha: 0.4),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class ThemePanel extends StatelessWidget {
  const ThemePanel({required this.tokens, required this.child, super.key});

  final ThemeTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: scheme.surfaceTint,
      shadowColor: scheme.shadow,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.panelRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
