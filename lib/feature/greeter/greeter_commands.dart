import 'greeter_state.dart';

sealed class GreeterCommand {
  const GreeterCommand();
}

class SelectUserCommand extends GreeterCommand {
  const SelectUserCommand(this.user);

  final UserSummary user;
}

class BeginAuthenticationCommand extends GreeterCommand {
  const BeginAuthenticationCommand();
}

class RespondToPromptCommand extends GreeterCommand {
  const RespondToPromptCommand(this.response);

  final String response;
}

class CancelAuthenticationCommand extends GreeterCommand {
  const CancelAuthenticationCommand();
}

class SelectSessionCommand extends GreeterCommand {
  const SelectSessionCommand(this.session);

  final SessionSummary session;
}

class StartSelectedSessionCommand extends GreeterCommand {
  const StartSelectedSessionCommand();
}

class RequestPowerActionCommand extends GreeterCommand {
  const RequestPowerActionCommand(this.action);

  final PowerAction action;
}

class RetryAuthenticationCommand extends GreeterCommand {
  const RetryAuthenticationCommand();
}

class RetryPromptCommand extends GreeterCommand {
  const RetryPromptCommand();
}

class ReconnectServiceCommand extends GreeterCommand {
  const ReconnectServiceCommand();
}

class RetrySessionCatalogCommand extends GreeterCommand {
  const RetrySessionCatalogCommand();
}

class WakeGreeterCommand extends GreeterCommand {
  const WakeGreeterCommand();
}

class SleepGreeterCommand extends GreeterCommand {
  const SleepGreeterCommand();
}

/// Maps a recovery offered by the feature to the command that performs it.
GreeterCommand recoveryCommand(GreeterRecovery recovery) {
  return switch (recovery) {
    GreeterRecovery.retryPrompt => const RetryPromptCommand(),
    GreeterRecovery.reconnectService => const ReconnectServiceCommand(),
    GreeterRecovery.selectUser ||
    GreeterRecovery.selectSession => const CancelAuthenticationCommand(),
    GreeterRecovery.retryAuthentication ||
    GreeterRecovery.retrySessionCatalog => const RetryAuthenticationCommand(),
  };
}
