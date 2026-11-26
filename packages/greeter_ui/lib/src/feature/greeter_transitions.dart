import 'greeter_effect.dart';
import 'greeter_state.dart';
import 'ports/greeter_gateway.dart';

/// Session id or name fragments preferred when the user has no stored choice.
const _preferredSessionNames = ['hyprland', 'sway'];

bool canSelectGreeterUser(
  GreeterState state, {
  required bool beginInFlight,
  required bool sessionStartInFlight,
}) {
  if (state.serviceMode != ServiceMode.ready ||
      state.dormant ||
      beginInFlight ||
      sessionStartInFlight) {
    return false;
  }
  if (state.authMode == AuthMode.userSelection ||
      state.authMode == AuthMode.prompting ||
      (state.authMode == AuthMode.submitting &&
          state.prompt?.kind == PromptKind.info)) {
    return true;
  }
  return state.authMode == AuthMode.error &&
      (state.authError?.recovery == GreeterRecovery.retryAuthentication ||
          state.authError?.recovery == GreeterRecovery.retryPrompt);
}

SessionSummary? findPreferredSession(
  List<SessionSummary> sessions, {
  SessionSummary? current,
  String? storedSessionId,
}) {
  // A refresh preserves the current choice before consulting persistence.
  // Only IDs present in this catalog may be restored; preferences are hints,
  // not authority to launch a session that the backend no longer exposes.
  if (current != null &&
      sessions.any((candidate) => candidate.id == current.id)) {
    return current;
  }
  if (storedSessionId != null) {
    for (final session in sessions) {
      if (session.id == storedSessionId) {
        return session;
      }
    }
  }
  for (final preferred in _preferredSessionNames) {
    for (final session in sessions) {
      if (session.id.toLowerCase().contains(preferred) ||
          session.name.toLowerCase().contains(preferred)) {
        return session;
      }
    }
  }
  return sessions.isEmpty ? null : sessions.first;
}

String getGreeterErrorMessage(Object error) {
  return error is GreeterGatewayException
      ? error.message
      : serviceUnavailableMessage;
}

GreeterError createGreeterError(
  Object error, {
  required GreeterErrorKind fallbackKind,
  required GreeterRecovery recovery,
}) {
  return (
    kind: error is GreeterGatewayException ? error.kind : fallbackKind,
    message: getGreeterErrorMessage(error),
    recovery: recovery,
  );
}

({GreeterState state, FeatureEffect? effect}) applyPromptTransition(
  GreeterState state,
  PromptKind kind,
  String text,
) {
  switch (kind) {
    case PromptKind.visible:
    case PromptKind.secret:
      return (
        state: state.copyWith(
          authMode: AuthMode.prompting,
          prompt: (kind: kind, text: text),
          backendAuthState: BackendAuthState.waitingForInput,
          authError: null,
        ),
        effect: state.dormant ? null : const FocusCredentialEffect(),
      );
    case PromptKind.error:
      return (state: state.copyWith(promptError: text), effect: null);
    case PromptKind.info:
      // PAM acknowledges passive authentication in the backend. Keep its
      // instructions visible for the scan without requesting credentials.
      return (
        state: state.copyWith(
          authMode: AuthMode.submitting,
          prompt: (kind: kind, text: text),
          authError: null,
          promptError: null,
        ),
        effect: const ClearCredentialEffect(),
      );
  }
}

({
  GreeterState state,
  bool clearAttempt,
  bool shouldStartSession,
  FeatureEffect? effect,
})
applyBackendAuthStateTransition(
  GreeterState state,
  BackendAuthState backendState,
  String detail,
) {
  final failed = backendState == BackendAuthState.failed;
  final clearPrompt = failed || backendState == BackendAuthState.authenticated;
  final preserveAuthMode =
      backendState == BackendAuthState.waitingForInput ||
      backendState == BackendAuthState.unknown;

  // Prompt carries the input kind and text; WaitingForInput only confirms
  // protocol progress. Keeping the current mode avoids undoing that prompt
  // or a local input error when the following state signal arrives.
  final nextMode = switch (backendState) {
    BackendAuthState.creatingSession ||
    BackendAuthState.promptPending ||
    BackendAuthState.submittingResponse ||
    BackendAuthState.resolvingSession ||
    BackendAuthState.startingSession ||
    BackendAuthState.cancelling => AuthMode.submitting,
    BackendAuthState.authenticated =>
      state.selectedSession == null
          ? AuthMode.sessionSelection
          : AuthMode.submitting,
    BackendAuthState.handingOff => AuthMode.handingOff,
    BackendAuthState.failed => AuthMode.error,
    BackendAuthState.idle => AuthMode.userSelection,
    BackendAuthState.waitingForInput ||
    BackendAuthState.unknown => state.authMode,
  };

  final authError = failed
      ? (
          kind: GreeterErrorKind.authentication,
          message: detail,
          recovery: GreeterRecovery.retryAuthentication,
        )
      : preserveAuthMode
      ? state.authError
      : null;

  return (
    state: state.copyWith(
      authMode: nextMode,
      backendAuthState: backendState,
      authError: authError,
      promptError: clearPrompt ? null : state.promptError,
      prompt: clearPrompt ? null : state.prompt,
    ),
    clearAttempt: failed,
    shouldStartSession:
        backendState == BackendAuthState.authenticated &&
        state.selectedSession != null,
    effect: failed ? const ClearCredentialEffect() : null,
  );
}

GreeterState resetGreeterStateToUserSelection(
  GreeterState state, {
  bool clearSelectedUser = false,
  ServiceMode? serviceMode,
}) {
  return state.copyWith(
    serviceMode: serviceMode,
    authMode: AuthMode.userSelection,
    selectedUser: clearSelectedUser ? null : state.selectedUser,
    prompt: null,
    authError: null,
    promptError: null,
    catalogError: state.sessions.isNotEmpty ? null : state.catalogError,
    catalogMode: state.sessions.isNotEmpty
        ? CatalogMode.ready
        : state.catalogMode,
    backendAuthState: BackendAuthState.idle,
  );
}
