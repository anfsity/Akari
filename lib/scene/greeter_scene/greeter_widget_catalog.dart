import 'dart:async';
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
      SceneNodeKind.dateTime => const _SceneClock(),
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
          onSelect: (user) {
            onDispatch(SelectUserCommand(user));
          },
        ),
      ),
      SceneNodeKind.accountName => SceneRegion<AccountPickerSlots>(
        valueListenable: feature.accountPickerSlots,
        builder: (context, account) => Center(
          child: Text(
            account.selected?.displayName ?? 'Choose account',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              shadows: const [Shadow(color: Color(0xaa000000), blurRadius: 12)],
            ),
          ),
        ),
      ),
      SceneNodeKind.sessionPicker => SceneRegion<SessionPickerSlots>(
        valueListenable: feature.sessionPickerSlots,
        builder: (context, session) => _SessionPill(
          session: session,
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
          onRespond: onRespond,
        ),
      ),
      SceneNodeKind.primaryAction => ListenableBuilder(
        listenable: Listenable.merge([
          feature.authPromptSlots,
          feature.continueSlots,
        ]),
        builder: (context, child) {
          final auth = (feature.authPromptSlots).value;
          final continueAction = (feature.continueSlots).value;
          return _PrimaryAction(
            auth: auth,
            continueAction: continueAction,
            onBegin: () {
              onDispatch(const BeginAuthenticationCommand());
            },
            onRespond: onRespond,
            onRetry: (recovery) {
              switch (recovery) {
                case GreeterRecovery.retryPrompt:
                  onDispatch(const RetryPromptCommand());
                case GreeterRecovery.reconnectService:
                  onDispatch(const ReconnectServiceCommand());
                case GreeterRecovery.selectUser:
                case GreeterRecovery.selectSession:
                  onDispatch(const CancelAuthenticationCommand());
                case GreeterRecovery.retryAuthentication:
                case GreeterRecovery.retrySessionCatalog:
                  onDispatch(const RetryAuthenticationCommand());
              }
            },
          );
        },
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

class _SceneClock extends StatefulWidget {
  const _SceneClock();

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
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        _formatDate(_now),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: const Color(0xffd9b16d),
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(color: Color(0x99000000), blurRadius: 10)],
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[value.weekday - 1]}, ${months[value.month - 1]} ${value.day}';
}

class _PowerActions extends StatelessWidget {
  const _PowerActions({required this.power, required this.onAction});

  final PowerSlots power;
  final ValueChanged<PowerAction> onAction;

  @override
  Widget build(BuildContext context) {
    final enabled = power.mode != PowerMode.executing;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _PowerIcon(
          tooltip: 'Suspend',
          icon: Icons.dark_mode_outlined,
          enabled: enabled,
          onPressed: () => onAction(PowerAction.suspend),
        ),
        _PowerIcon(
          tooltip: 'Reboot',
          icon: Icons.restart_alt,
          enabled: enabled,
          onPressed: () => onAction(PowerAction.reboot),
        ),
        _PowerIcon(
          tooltip: 'Power off',
          icon: Icons.power_settings_new,
          enabled: enabled,
          onPressed: () => onAction(PowerAction.powerOff),
        ),
      ],
    );
  }
}

class _PowerIcon extends StatelessWidget {
  const _PowerIcon({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
      iconSize: 20,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      color: Colors.white,
      disabledColor: Colors.white38,
      style: IconButton.styleFrom(
        minimumSize: const Size(34, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Colors.black.withValues(alpha: 0.22),
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 32,
            offset: Offset(0, 18),
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
  const _AccountAvatar({required this.account, required this.onSelect});

  final AccountPickerSlots account;
  final ValueChanged<UserSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = account.selected;
    return Tooltip(
      message: 'Choose account',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _showAccountPicker(context, account, onSelect),
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.35),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: Center(
                child: selected == null
                    ? const Icon(Icons.person_outline, size: 36)
                    : Text(
                        selected.displayName.characters.first.toUpperCase(),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
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
  ValueChanged<UserSummary> onSelect,
) async {
  final selected = await showModalBottomSheet<UserSummary>(
    context: context,
    backgroundColor: const Color(0xee11171b),
    builder: (context) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final user in account.users)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(user.displayName),
                trailing: account.selected?.id == user.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(context).pop(user),
              ),
          ],
        ),
      );
    },
  );
  if (selected != null) {
    onSelect(selected);
  }
}

class _SessionPill extends StatelessWidget {
  const _SessionPill({
    required this.session,
    required this.onSelect,
    required this.onRetry,
  });

  final SessionPickerSlots session;
  final ValueChanged<SessionSummary> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (session.mode) {
      CatalogMode.loading => const Center(child: CircularProgressIndicator()),
      CatalogMode.failed => Center(
        child: TextButton(
          onPressed: onRetry,
          child: Text(session.error?.message ?? 'Retry sessions'),
        ),
      ),
      CatalogMode.empty when session.sessions.isEmpty => const Center(
        child: Text('No desktop sessions available.'),
      ),
      CatalogMode.ready || CatalogMode.empty => PopupMenuButton<SessionSummary>(
        tooltip: 'Choose a session',
        onSelected: onSelect,
        position: PopupMenuPosition.under,
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
                  ),
                  const SizedBox(width: 12),
                  Text(item.name),
                ],
              ),
            ),
        ],
        child: _PillSurface(
          child: Row(
            children: [
              const Icon(Icons.desktop_windows_outlined, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  session.selected?.name ?? 'Choose a session',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.expand_more),
            ],
          ),
        ),
      ),
    };
  }
}

class _PillSurface extends StatelessWidget {
  const _PillSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: child,
      ),
    );
  }
}

class _CredentialField extends StatelessWidget {
  const _CredentialField({
    required this.auth,
    required this.controller,
    required this.focusNode,
    required this.onRespond,
  });

  final AuthPromptSlots auth;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onRespond;

  @override
  Widget build(BuildContext context) {
    final enabled = auth.mode == AuthMode.prompting;
    final secret = auth.prompt?.kind == PromptKind.secret;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: secret,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onRespond(),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        hintText: enabled ? auth.prompt?.text ?? 'Password' : 'Enter Password',
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.auth,
    required this.continueAction,
    required this.onBegin,
    required this.onRespond,
    required this.onRetry,
  });

  final AuthPromptSlots auth;
  final ContinueSlots continueAction;
  final VoidCallback onBegin;
  final VoidCallback onRespond;
  final ValueChanged<GreeterRecovery> onRetry;

  @override
  Widget build(BuildContext context) {
    final enabled = switch (auth.mode) {
      AuthMode.userSelection => continueAction.enabled,
      AuthMode.prompting => true,
      AuthMode.error => auth.error?.recovery != null,
      _ => false,
    };

    final onPressed = switch (auth.mode) {
      AuthMode.userSelection => onBegin,
      AuthMode.prompting => onRespond,
      AuthMode.error => () => onRetry(auth.error!.recovery),
      _ => null,
    };

    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
          child: auth.mode == AuthMode.submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_forward),
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
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.white70,
          shadows: const [Shadow(color: Color(0xaa000000), blurRadius: 8)],
        ),
      ),
    );
  }
}
