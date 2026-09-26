import 'package:flutter/material.dart';
import 'package:mozais_theme_sdk/mozais_theme_sdk.dart';

class GreeterStatusLine extends StatelessWidget {
  const GreeterStatusLine({
    required this.service,
    required this.auth,
    required this.session,
    super.key,
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
