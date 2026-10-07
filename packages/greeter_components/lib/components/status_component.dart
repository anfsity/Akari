import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

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
    // Service failure takes precedence because authentication cannot recover
    // without it. During a usable prompt, keep rejection text ahead of catalog
    // errors so the user sees why the previous credential was rejected.
    final message = switch (service.mode) {
      ServiceMode.starting => 'Starting greeter service...',
      ServiceMode.unavailable =>
        service.error?.message ?? 'Greeter service unavailable.',
      ServiceMode.ready => switch (auth.mode) {
        AuthMode.error => auth.error?.message ?? 'Authentication failed.',
        AuthMode.prompting => auth.promptError ?? session.error?.message ?? '',
        AuthMode.submitting =>
          auth.promptError ??
              (auth.prompt?.kind == PromptKind.info
                  ? auth.prompt!.text
                  : 'Signing in...'),
        AuthMode.handingOff => 'Starting session...',
        _ => session.error?.message ?? '',
      },
    };

    if (message.isEmpty) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                service.mode == ServiceMode.unavailable ||
                    auth.mode == AuthMode.error ||
                    auth.promptError != null ||
                    session.error != null
                ? scheme.error
                : scheme.primary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
