import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import '../../feature/greeter/greeter_commands.dart';
import '../../feature/greeter/greeter_feature.dart';
import '../../feature/greeter/greeter_slots.dart';
import '../../feature/greeter/greeter_state.dart';
import '../scene_region.dart';

class GreeterWidgetCatalog {
  const GreeterWidgetCatalog({
    required this.feature,
    required this.theme,
    required this.credentialController,
    required this.credentialFocusNode,
    required this.onDispatch,
    required this.onRespond,
  });

  final GreeterFeature feature;
  final ThemeBundle theme;
  final TextEditingController credentialController;
  final FocusNode credentialFocusNode;
  final ValueChanged<GreeterCommand> onDispatch;
  final VoidCallback onRespond;

  Widget build(BuildContext context, SceneNode node) {
    return switch (node.kind) {
      SceneNodeKind.dateTime => _SceneClock(
        variant: node.properties['variant'] == 'time'
            ? _ClockVariant.time
            : _ClockVariant.date,
      ),
      SceneNodeKind.powerActions => SceneRegion<PowerSlots>(
        valueListenable: feature.powerSlots,
        builder: (context, power) => _PowerActions(
          power: power,
          onAction: (action) {
            onDispatch(RequestPowerActionCommand(action));
          },
        ),
      ),
      SceneNodeKind.glassPanel => _GlassPanel(
        theme: theme,
        child: const SizedBox.expand(),
      ),
      SceneNodeKind.avatar => SceneRegion<AccountPickerSlots>(
        valueListenable: feature.accountPickerSlots,
        builder: (context, account) => _AccountAvatar(
          account: account,
          tokens: theme.tokens,
          onSelect: (user) {
            onDispatch(SelectUserCommand(user));
          },
        ),
      ),
      SceneNodeKind.accountName => SceneRegion<AccountPickerSlots>(
        valueListenable: feature.accountPickerSlots,
        builder: (context, account) => _AccountName(account: account),
      ),
      SceneNodeKind.sessionPicker => SceneRegion<SessionPickerSlots>(
        valueListenable: feature.sessionPickerSlots,
        builder: (context, session) => _SessionPill(
          session: session,
          tokens: theme.tokens,
          onSelect: (value) {
            onDispatch(SelectSessionCommand(value));
          },
          onRetry: () {
            onDispatch(const RetrySessionCatalogCommand());
          },
        ),
      ),
      SceneNodeKind.credentialField => SceneRegion<AuthPromptSlots>(
        valueListenable: feature.authPromptSlots,
        builder: (context, auth) => _CredentialField(
          auth: auth,
          controller: credentialController,
          focusNode: credentialFocusNode,
        ),
      ),
      SceneNodeKind.primaryAction => SceneRegion<AuthPromptSlots>(
        valueListenable: feature.authPromptSlots,
        builder: (context, auth) => _PrimaryAction(
          auth: auth,
          onRespond: onRespond,
          onRetry: (recovery) {
            onDispatch(recoveryCommand(recovery));
          },
        ),
      ),
      SceneNodeKind.status => ListenableBuilder(
        listenable: Listenable.merge([
          feature.serviceSlots,
          feature.authPromptSlots,
          feature.sessionPickerSlots,
        ]),
        builder: (context, child) {
          final service = (feature.serviceSlots).value;
          final auth = (feature.authPromptSlots).value;
          final session = (feature.sessionPickerSlots).value;
          return _StatusLine(service: service, auth: auth, session: session);
        },
      ),
      SceneNodeKind.background ||
      SceneNodeKind.accountPicker ||
      SceneNodeKind.secondaryAction ||
      SceneNodeKind.decoration => const SizedBox.shrink(),
    };
  }
}

enum _ClockVariant { date, time }

class _SceneClock extends StatefulWidget {
  const _SceneClock({required this.variant});

  final _ClockVariant variant;

  @override
  State<_SceneClock> createState() => _SceneClockState();
}

class _SceneClockState extends State<_SceneClock> {
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
    return switch (widget.variant) {
      _ClockVariant.date => Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _formatDate(_now),
            maxLines: 1,
            style: _clockStyle(context, fontSize: 20, weight: FontWeight.w500),
          ),
        ),
      ),
      _ClockVariant.time => Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _formatTime(_now),
            maxLines: 1,
            style: _clockStyle(context, fontSize: 120, weight: FontWeight.w300),
          ),
        ),
      ),
    };
  }
}

TextStyle _clockStyle(
  BuildContext context, {
  required double fontSize,
  required FontWeight weight,
}) {
  return TextStyle(
    color: Theme.of(context).colorScheme.primary,
    fontSize: fontSize,
    fontWeight: weight,
    height: 1.05,
    shadows: const [Shadow(color: Color(0x66000000), blurRadius: 12)],
  );
}

String _formatDate(DateTime value) {
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
  return '${weekdays[value.weekday - 1]}, ${months[value.month - 1]} ${value.day}';
}

String _formatTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _PowerActions extends StatelessWidget {
  const _PowerActions({required this.power, required this.onAction});

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

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.theme, required this.child});

  final ThemeBundle theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(theme.tokens.panelRadius);
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.tokens.glassColor,
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 40,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: child,
    );

    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!theme.tokens.allowBlur || disableAnimations) {
      return ClipRRect(borderRadius: radius, child: panel);
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: theme.tokens.blurSigma,
          sigmaY: theme.tokens.blurSigma,
        ),
        child: panel,
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.account,
    required this.tokens,
    required this.onSelect,
  });

  final AccountPickerSlots account;
  final ThemeTokens tokens;
  final ValueChanged<UserSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = account.selected;
    final accent = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: 'Choose account',
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: tokens.surfaceColor,
            shape: CircleBorder(
              side: BorderSide(color: tokens.surfaceVariantColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: account.canSelect
                  ? () => _showAccountPicker(context, account, tokens, onSelect)
                  : null,
              child: Center(
                child: selected == null
                    ? Icon(Icons.person_outline, size: 40, color: accent)
                    : _AccountAvatarImage(
                        user: selected,
                        accent: accent,
                        fontSize: 48,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showAccountPicker(
  BuildContext context,
  AccountPickerSlots account,
  ThemeTokens tokens,
  ValueChanged<UserSummary> onSelect,
) async {
  final selected = await showDialog<UserSummary>(
    context: context,
    builder: (context) {
      final accent = Theme.of(context).colorScheme.primary;
      return Dialog(
        backgroundColor: tokens.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: tokens.surfaceVariantColor),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260, maxHeight: 320),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(10),
            children: [
              for (final user in account.users)
                _UserTile(
                  user: user,
                  selected: account.selected?.id == user.id,
                  accent: accent,
                  tokens: tokens,
                  onTap: () => Navigator.of(context).pop(user),
                ),
            ],
          ),
        ),
      );
    },
  );
  if (selected != null) {
    onSelect(selected);
  }
}

class _AccountAvatarImage extends StatelessWidget {
  const _AccountAvatarImage({
    required this.user,
    required this.accent,
    required this.fontSize,
  });

  final UserSummary user;
  final Color accent;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (user.iconPath.isEmpty) {
      return _initial();
    }
    return Image.file(
      File(user.iconPath),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _initial(),
    );
  }

  Widget _initial() {
    return Text(
      user.displayName.characters.first.toUpperCase(),
      style: TextStyle(
        color: accent,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.selected,
    required this.accent,
    required this.tokens,
    required this.onTap,
  });

  final UserSummary user;
  final bool selected;
  final Color accent;
  final ThemeTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? tokens.surfaceVariantColor : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: selected ? accent : tokens.surfaceVariantColor,
                foregroundImage: user.iconPath.isEmpty
                    ? null
                    : FileImage(File(user.iconPath)),
                onForegroundImageError: user.iconPath.isEmpty
                    ? null
                    : (error, stackTrace) {},
                child: Text(
                  user.displayName.characters.first.toUpperCase(),
                  style: TextStyle(
                    color: selected ? Colors.white : accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  user.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check, size: 18, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountName extends StatelessWidget {
  const _AccountName({required this.account});

  final AccountPickerSlots account;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        account.selected?.displayName ?? 'Choose account',
        maxLines: 1,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SessionPill extends StatelessWidget {
  const _SessionPill({
    required this.session,
    required this.tokens,
    required this.onSelect,
    required this.onRetry,
  });

  final SessionPickerSlots session;
  final ThemeTokens tokens;
  final ValueChanged<SessionSummary> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: switch (session.mode) {
          CatalogMode.loading => const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          CatalogMode.failed => Center(
            child: TextButton(
              onPressed: onRetry,
              child: Text(session.error?.message ?? 'Retry sessions'),
            ),
          ),
          CatalogMode.empty when session.sessions.isEmpty => Center(
            child: Text(
              'No desktop sessions available.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
          CatalogMode.ready || CatalogMode.empty => _SessionMenu(
            session: session,
            tokens: tokens,
            onSelect: onSelect,
          ),
        },
      ),
    );
  }
}

class _SessionMenu extends StatelessWidget {
  const _SessionMenu({
    required this.session,
    required this.tokens,
    required this.onSelect,
  });

  final SessionPickerSlots session;
  final ThemeTokens tokens;
  final ValueChanged<SessionSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        return PopupMenuButton<SessionSummary>(
          tooltip: 'Choose a session',
          onSelected: onSelect,
          position: PopupMenuPosition.under,
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          itemBuilder: (context) => [
            for (final item in session.sessions)
              PopupMenuItem(
                value: item,
                child: Row(
                  children: [
                    Icon(
                      session.selected?.id == item.id
                          ? Icons.check_circle
                          : Icons.desktop_windows_outlined,
                      size: 18,
                      color: session.selected?.id == item.id ? accent : null,
                    ),
                    const SizedBox(width: 12),
                    Text(item.name),
                  ],
                ),
              ),
          ],
          child: _PillSurface(
            tokens: tokens,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.desktop_windows_outlined, size: 16, color: accent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    session.selected?.name ?? 'Choose session',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (session.sessions.length > 1)
                  Icon(Icons.arrow_drop_down, size: 18, color: accent),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PillSurface extends StatelessWidget {
  const _PillSurface({required this.tokens, required this.child});

  final ThemeTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.surfaceVariantColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(child: child),
      ),
    );
  }
}

class _CredentialField extends StatelessWidget {
  const _CredentialField({
    required this.auth,
    required this.controller,
    required this.focusNode,
  });

  final AuthPromptSlots auth;
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final enabled = auth.mode == AuthMode.prompting;
    final secret = auth.prompt?.kind == PromptKind.secret;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      // The node stays mounted through its exit transition after the prompt is
      // cleared, so never reveal a response once the field stops accepting it.
      obscureText: secret || !enabled,
      textInputAction: TextInputAction.done,
      textAlign: TextAlign.center,
      textAlignVertical: TextAlignVertical.center,
      style: const TextStyle(color: Colors.white, fontSize: 18),
      decoration: InputDecoration(
        hintText: enabled ? auth.prompt?.text ?? 'Password' : 'Enter Password',
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.auth,
    required this.onRespond,
    required this.onRetry,
  });

  final AuthPromptSlots auth;
  final VoidCallback onRespond;
  final ValueChanged<GreeterRecovery> onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final error = auth.error;
    final VoidCallback? onPressed;
    final Widget icon;
    switch (auth.mode) {
      case AuthMode.prompting:
        onPressed = onRespond;
        icon = const Icon(Icons.arrow_forward, size: 30);
      case AuthMode.submitting:
        onPressed = null;
        icon = SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.onPrimary,
          ),
        );
      case AuthMode.error:
        if (error == null) {
          return const SizedBox.shrink();
        }
        onPressed = () => onRetry(error.recovery);
        icon = const Icon(Icons.refresh, size: 30);
      case AuthMode.userSelection:
      case AuthMode.sessionSelection:
      case AuthMode.handingOff:
        return const SizedBox.shrink();
    }

    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            disabledBackgroundColor: colorScheme.primary.withValues(
              alpha: 0.4,
            ),
            disabledForegroundColor: colorScheme.onPrimary.withValues(
              alpha: 0.5,
            ),
          ),
          child: icon,
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.service,
    required this.auth,
    required this.session,
  });

  final ServiceSlots service;
  final AuthPromptSlots auth;
  final SessionPickerSlots session;

  @override
  Widget build(BuildContext context) {
    final message = switch (service.mode) {
      ServiceMode.starting => 'Starting greeter service...',
      ServiceMode.unavailable =>
        service.error?.message ?? 'Greeter service unavailable.',
      ServiceMode.ready => switch (auth.mode) {
        AuthMode.error => auth.error?.message ?? 'Authentication failed.',
        AuthMode.prompting => auth.promptError ?? session.error?.message ?? '',
        AuthMode.submitting => 'Working...',
        AuthMode.handingOff => 'Starting session...',
        _ => session.error?.message ?? '',
      },
    };

    if (message.isEmpty) {
      return const SizedBox.shrink();
    }

    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 14,
          shadows: const [Shadow(color: Color(0xaa000000), blurRadius: 8)],
        ),
      ),
    );
  }
}
