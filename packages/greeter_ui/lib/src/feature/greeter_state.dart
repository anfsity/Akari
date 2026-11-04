import 'package:theme_sdk/theme_sdk.dart';

export 'package:theme_sdk/theme_sdk.dart'
    show
        AuthMode,
        CatalogMode,
        GreeterError,
        GreeterErrorKind,
        GreeterRecovery,
        PowerAction,
        PowerMode,
        PromptKind,
        PromptState,
        ServiceMode,
        SessionSummary,
        UserSummary;

enum BackendAuthState {
  idle,
  creatingSession,
  promptPending,
  waitingForInput,
  submittingResponse,
  authenticated,
  resolvingSession,
  startingSession,
  handingOff,
  cancelling,
  failed,
  unknown,
}

const Object _unset = Object();

/// Immutable frontend snapshot, separate from the backend protocol phase.
///
/// Service, catalog, authentication, and power errors remain independent so
/// failure in one operation does not erase another operation's recovery state.
/// Lists are copied on construction to prevent later caller mutations from
/// bypassing slot notifications. Credential responses never belong here.
class GreeterState {
  GreeterState({
    required this.serviceMode,
    required this.catalogMode,
    required this.authMode,
    required List<UserSummary> users,
    required List<SessionSummary> sessions,
    required this.selectedUser,
    required this.selectedSession,
    required this.prompt,
    required this.promptError,
    required this.serviceError,
    required this.authError,
    required this.catalogError,
    required this.powerError,
    required this.powerMode,
    required this.backendAuthState,
    required this.dormant,
  }) : users = List.unmodifiable(users),
       sessions = List.unmodifiable(sessions);

  factory GreeterState.initial() {
    return GreeterState(
      serviceMode: ServiceMode.starting,
      catalogMode: CatalogMode.empty,
      authMode: AuthMode.userSelection,
      users: <UserSummary>[],
      sessions: <SessionSummary>[],
      selectedUser: null,
      selectedSession: null,
      prompt: null,
      promptError: null,
      serviceError: null,
      authError: null,
      catalogError: null,
      powerError: null,
      powerMode: PowerMode.idle,
      backendAuthState: BackendAuthState.idle,
      dormant: true,
    );
  }

  final ServiceMode serviceMode;
  final CatalogMode catalogMode;
  final AuthMode authMode;
  final List<UserSummary> users;
  final List<SessionSummary> sessions;
  final UserSummary? selectedUser;
  final SessionSummary? selectedSession;
  final PromptState? prompt;

  /// Display-safe rejection shown beside an active prompt until the user
  /// answers it again. Unlike [authError], it does not end the attempt.
  final String? promptError;
  final GreeterError? serviceError;
  final GreeterError? authError;
  final GreeterError? catalogError;
  final GreeterError? powerError;
  final PowerMode powerMode;
  final BackendAuthState backendAuthState;

  /// Whether the greeter shows only the idle background until the user wakes
  /// it. Service errors force it awake so the failure stays visible.
  final bool dormant;

  /// Omitted arguments preserve existing values; passing `null` explicitly
  /// clears nullable fields such as prompts, selections, or errors.
  GreeterState copyWith({
    ServiceMode? serviceMode,
    CatalogMode? catalogMode,
    AuthMode? authMode,
    List<UserSummary>? users,
    List<SessionSummary>? sessions,
    Object? selectedUser = _unset,
    Object? selectedSession = _unset,
    Object? prompt = _unset,
    Object? promptError = _unset,
    Object? serviceError = _unset,
    Object? authError = _unset,
    Object? catalogError = _unset,
    Object? powerError = _unset,
    PowerMode? powerMode,
    BackendAuthState? backendAuthState,
    bool? dormant,
  }) {
    return GreeterState(
      serviceMode: serviceMode ?? this.serviceMode,
      catalogMode: catalogMode ?? this.catalogMode,
      authMode: authMode ?? this.authMode,
      users: users ?? this.users,
      sessions: sessions ?? this.sessions,
      selectedUser: identical(selectedUser, _unset)
          ? this.selectedUser
          : selectedUser as UserSummary?,
      selectedSession: identical(selectedSession, _unset)
          ? this.selectedSession
          : selectedSession as SessionSummary?,
      prompt: identical(prompt, _unset) ? this.prompt : prompt as PromptState?,
      promptError: identical(promptError, _unset)
          ? this.promptError
          : promptError as String?,
      serviceError: identical(serviceError, _unset)
          ? this.serviceError
          : serviceError as GreeterError?,
      authError: identical(authError, _unset)
          ? this.authError
          : authError as GreeterError?,
      catalogError: identical(catalogError, _unset)
          ? this.catalogError
          : catalogError as GreeterError?,
      powerError: identical(powerError, _unset)
          ? this.powerError
          : powerError as GreeterError?,
      powerMode: powerMode ?? this.powerMode,
      backendAuthState: backendAuthState ?? this.backendAuthState,
      dormant: dormant ?? this.dormant,
    );
  }
}
