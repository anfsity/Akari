import 'package:flutter/material.dart';
import 'package:mozais_theme_sdk/mozais_theme_sdk.dart';

class CredentialField extends StatelessWidget {
  const CredentialField({
    required this.auth,
    required this.controller,
    required this.focusNode,
    super.key,
  });

  final AuthPromptSlots auth;
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = auth.mode == AuthMode.prompting;
    final hintText = auth.mode == AuthMode.prompting
        ? auth.prompt?.text ?? 'Password'
        : 'Enter Password';
    final inputTheme = InputDecorationTheme.of(context);
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) {
        final border = !enabled
            ? inputTheme.disabledBorder ?? inputTheme.border
            : focusNode.hasFocus
            ? inputTheme.focusedBorder ?? inputTheme.enabledBorder
            : inputTheme.enabledBorder;
        final borderRadius = border is OutlineInputBorder
            ? border.borderRadius
            : BorderRadius.zero;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: inputTheme.fillColor,
            borderRadius: borderRadius,
            border: Border.fromBorderSide(
              border?.borderSide ?? BorderSide.none,
            ),
          ),
          child: child,
        );
      },
      child: Align(
        alignment: Alignment.center,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          obscureText: auth.prompt?.kind == PromptKind.secret || !enabled,
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            filled: false,
            contentPadding: inputTheme.contentPadding,
            isDense: inputTheme.isDense,
          ),
        ),
      ),
    );
  }
}

class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    required this.auth,
    required this.onRespond,
    required this.onRetry,
    super.key,
  });

  final AuthPromptSlots auth;
  final VoidCallback onRespond;
  final ValueChanged<GreeterRecovery> onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final error = auth.error;
    final action = switch (auth.mode) {
      AuthMode.prompting => (
        onRespond,
        const Icon(Icons.arrow_forward, size: 30),
      ),
      AuthMode.submitting => (
        null,
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.onPrimary,
          ),
        ),
      ),
      AuthMode.error when error != null => (
        () => onRetry(error.recovery),
        const Icon(Icons.refresh, size: 30),
      ),
      AuthMode.error ||
      AuthMode.userSelection ||
      AuthMode.sessionSelection ||
      AuthMode.handingOff => null,
    };
    if (action == null) {
      return const SizedBox.shrink();
    }
    final (onPressed, icon) = action;

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
            disabledBackgroundColor: colorScheme.primary.withValues(alpha: 0.4),
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
