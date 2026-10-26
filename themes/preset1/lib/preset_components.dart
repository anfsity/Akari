import 'package:flutter/material.dart';
import 'package:greeter_components/greeter_components.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'preset_style.dart';
import 'weekday_lettering.dart';

/// The scene owns placement. Components borrow the host's authentication
/// controls so keyboard dispatch, prompts and recovery keep their existing
/// owner even though the visual composition has no form or panel.
class PresetComponents implements GreeterThemeComponents {
  PresetComponents(this.theme) : _standard = StandardGreeterComponents(theme);

  final GreeterThemeContext theme;
  final StandardGreeterComponents _standard;

  @override
  Widget build(BuildContext context, SceneNode node) {
    final host = theme.host;
    final component = switch (node.componentId) {
      'presetClock' => _PresetClock(
        reflected: node.properties['variant'] == 'reflected',
        compact: node.properties['variant'] == 'compact',
      ),
      'inscription' => _PresetInscription(
        title: node.properties['title']!,
        subtitle: node.properties['subtitle'] ?? '',
        light: node.properties['tone'] == 'light',
      ),
      'account' => SceneRegion<AccountPickerSlots>(
        valueListenable: host.accountPickerSlots,
        builder: (context, account) => _SceneChoice<UserSummary>(
          label: 'Choose account',
          caption: 'IDENTITY',
          text: account.selected?.displayName ?? 'Choose account',
          color: presetInk,
          enabled: account.canSelect,
          entries: [
            for (final user in account.users)
              PopupMenuItem(value: user, child: Text(user.displayName)),
          ],
          onSelected: host.onSelectUser,
        ),
      ),
      'session' => SceneRegion<SessionPickerSlots>(
        valueListenable: host.sessionPickerSlots,
        builder: (context, session) => switch (session.mode) {
          CatalogMode.loading => const Center(child: Text('Finding desktops…')),
          CatalogMode.failed => TextButton(
            onPressed: host.onRetrySessionCatalog,
            child: Text(session.error?.message ?? 'Retry desktops ↻'),
          ),
          CatalogMode.empty => const Center(
            child: Text('No desktops available'),
          ),
          CatalogMode.ready => _SceneChoice<SessionSummary>(
            label: 'Choose a session',
            caption: 'DESTINATION',
            text: session.selected?.name ?? 'Choose desktop',
            color: presetPaper,
            entries: [
              for (final item in session.sessions)
                PopupMenuItem(value: item, child: Text(item.name)),
            ],
            onSelected: host.onSelectSession,
          ),
        },
      ),
      'credential' => _PresetCredential(host: host),
      'enter' => Column(
        children: [
          const Text(
            'E N T E R',
            style: TextStyle(fontSize: 12, color: presetPaper),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                host.serviceSlots,
                host.authPromptSlots,
              ]),
              builder: (context, _) => PrimaryAction(
                service: host.serviceSlots.value,
                auth: host.authPromptSlots.value,
                filled: false,
                foregroundColor: presetPaper,
                onRespond: host.onRespondToPrompt,
                onStartSession: host.onStartSession,
                onRetry: host.onRetry,
              ),
            ),
          ),
        ],
      ),
      'power' => Column(
        children: [
          Expanded(
            child: SceneRegion<PowerSlots>(
              valueListenable: host.powerSlots,
              builder: (context, power) => PowerActions(
                power: power,
                onAction: host.onRequestPowerAction,
              ),
            ),
          ),
          SceneRegion<PowerSlots>(
            valueListenable: host.powerSlots,
            builder: (context, power) => power.error == null
                ? const SizedBox.shrink()
                : Semantics(
                    liveRegion: true,
                    child: Text(
                      power.error!.message,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      _ => _standard.build(context, node),
    };
    return ScaledNodeRegion(
      node: node,
      canvas: theme.canvas,
      child: component,
    );
  }
}

class _SceneChoice<T> extends StatelessWidget {
  const _SceneChoice({
    required this.label,
    required this.caption,
    required this.text,
    required this.color,
    required this.entries,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final String caption;
  final String text;
  final Color color;
  final List<PopupMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: PopupMenuButton<T>(
        tooltip: label,
        enabled: enabled,
        onSelected: onSelected,
        itemBuilder: (context) => entries,
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 256, maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                caption,
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 4,
                  color: color.withValues(alpha: .7),
                ),
              ),
              const SizedBox(height: 13),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 28,
                      letterSpacing: 3,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.expand_more, size: 18, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PresetCredential extends StatelessWidget {
  const _PresetCredential({required this.host});

  final GreeterHost host;

  @override
  Widget build(BuildContext context) => SceneRegion<AuthPromptSlots>(
    valueListenable: host.authPromptSlots,
    builder: (context, auth) => Column(
      children: [
        const Text(
          'U N L O C K',
          style: TextStyle(fontSize: 12, color: Color(0xffa9adbf)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: CredentialField(
            auth: auth,
            controller: host.credentialController,
            focusNode: host.credentialFocusNode,
          ),
        ),
        ListenableBuilder(
          listenable: host.credentialFocusNode,
          builder: (context, child) => AnimatedOpacity(
            opacity: host.credentialFocusNode.hasFocus ? 1 : .25,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: const Text(
              '·  ·  ·',
              style: TextStyle(fontSize: 14, color: presetPaper),
            ),
          ),
        ),
      ],
    ),
  );
}

class _PresetInscription extends StatelessWidget {
  const _PresetInscription({
    required this.title,
    required this.subtitle,
    required this.light,
  });

  final String title;
  final String subtitle;
  final bool light;

  @override
  Widget build(BuildContext context) => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subtitle.isNotEmpty) ...[
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 23,
                letterSpacing: 12,
                color: (light ? presetPaper : presetInk).withValues(alpha: .8),
              ),
            ),
            const SizedBox(height: 18),
          ],
          Text(
            title,
            style: TextStyle(
              fontSize: subtitle.isEmpty ? 12 : 25,
              letterSpacing: subtitle.isEmpty ? 3 : 13,
              color: light ? presetPaper : presetInk,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PresetClock extends StatelessWidget {
  const _PresetClock({
    required this.reflected,
    required this.compact,
  });

  final bool reflected;
  final bool compact;

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  @override
  Widget build(BuildContext context) => MinuteClockBuilder(
    builder: (context, now) {
      final color = reflected ? presetPaper : presetInk;
      final time = formatClockTime(now);
      final day = WeekdayLettering(
        weekday: now.weekday,
        color: color,
        height: compact ? 24 : 48,
      );
      final date = Text(
        '${now.day} ${_months[now.month - 1]} ${now.year}',
        style: TextStyle(fontSize: 17, letterSpacing: 2, color: color),
      );
      final clock = Text(
        '— $time —',
        style: TextStyle(
          fontSize: 15,
          letterSpacing: 2,
          color: color.withValues(alpha: .8),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      return Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: compact ? 380 : 640,
            height: compact ? 130 : 140,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: reflected
                  ? [
                      clock,
                      const SizedBox(height: 8),
                      date,
                      const SizedBox(height: 14),
                      day,
                    ]
                  : [
                      day,
                      const SizedBox(height: 12),
                      date,
                      const SizedBox(height: 8),
                      clock,
                    ],
            ),
          ),
        ),
      );
    },
  );
}
