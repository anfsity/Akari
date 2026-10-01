import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'greeter_models.dart';
import 'greeter_slots.dart';

/// Typed greeter state and semantic actions available to compiled themes.
class GreeterHost {
  const GreeterHost({
    required this.serviceSlots,
    required this.authPromptSlots,
    required this.accountPickerSlots,
    required this.sessionPickerSlots,
    required this.powerSlots,
    required this.credentialController,
    required this.credentialFocusNode,
    required this.onSelectUser,
    required this.onSelectSession,
    required this.onRequestPowerAction,
    required this.onRetry,
    required this.onRetrySessionCatalog,
    required this.onRespondToPrompt,
  });

  final ValueListenable<ServiceSlots> serviceSlots;
  final ValueListenable<AuthPromptSlots> authPromptSlots;
  final ValueListenable<AccountPickerSlots> accountPickerSlots;
  final ValueListenable<SessionPickerSlots> sessionPickerSlots;
  final ValueListenable<PowerSlots> powerSlots;
  final TextEditingController credentialController;
  final FocusNode credentialFocusNode;
  final ValueChanged<UserSummary> onSelectUser;
  final ValueChanged<SessionSummary> onSelectSession;
  final ValueChanged<PowerAction> onRequestPowerAction;
  final ValueChanged<GreeterRecovery> onRetry;
  final VoidCallback onRetrySessionCatalog;
  final VoidCallback onRespondToPrompt;
}
