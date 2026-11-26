import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

class GreeterStatusLine extends StatelessWidget {
  const GreeterStatusLine({
    required this.service,
    required this.auth,
    required this.session,
    this.textAlign = TextAlign.center,
    super.key,
  });

  final ServiceSlots service;
  final AuthPromptSlots auth;
  final SessionPickerSlots session;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    // Service failure takes precedence because authentication cannot recover
    // without it. During a usable prompt, keep rejection text ahead of catalog
    // errors so the user sees why the previous credential was rejected.
    final (message, isError) = switch (service.mode) {
      ServiceMode.starting => ('Starting greeter service...', false),
      ServiceMode.unavailable => (
        service.error?.message ?? 'Greeter service unavailable.',
        true,
      ),
      ServiceMode.ready => switch (auth.mode) {
        AuthMode.error => (
          auth.error?.message ?? 'Authentication failed.',
          true,
        ),
        AuthMode.prompting => (
          auth.promptError ?? session.error?.message ?? '',
          auth.promptError != null || session.error != null,
        ),
        AuthMode.submitting =>
          auth.promptError != null
              ? (auth.promptError!, true)
              : (
                  auth.prompt?.kind == PromptKind.info
                      ? auth.prompt!.text
                      : 'Signing in...',
                  false,
                ),
        AuthMode.handingOff => ('Starting session...', false),
        _ => (session.error?.message ?? '', session.error != null),
      },
    };

    if (message.isEmpty) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Center(
        child: SizedBox(
          width: double.infinity,
          child: Text(
            message,
            textAlign: textAlign,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isError ? scheme.error : scheme.primary,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
