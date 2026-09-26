import 'package:mozais_theme_sdk/mozais_theme_sdk.dart';

export 'package:mozais_theme_sdk/mozais_theme_sdk.dart'
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

  GreeterState copyWith({
    ServiceMode? serviceMode,
    CatalogMode? catalogMode,
    AuthMode? authMode,
    List<UserSummary>? users,
    List<SessionSummary>? sessions,
    UserSummary? selectedUser,
    bool clearSelectedUser = false,
    SessionSummary? selectedSession,
    bool clearSelectedSession = false,
    PromptState? prompt,
    bool clearPrompt = false,
    String? promptError,
    bool clearPromptError = false,
    GreeterError? serviceError,
    bool clearServiceError = false,
    GreeterError? authError,
    bool clearAuthError = false,
    GreeterError? catalogError,
    bool clearCatalogError = false,
    GreeterError? powerError,
    bool clearPowerError = false,
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
      selectedUser: clearSelectedUser
          ? null
          : selectedUser ?? this.selectedUser,
      selectedSession: clearSelectedSession
          ? null
          : selectedSession ?? this.selectedSession,
      prompt: clearPrompt ? null : prompt ?? this.prompt,
      promptError: clearPromptError ? null : promptError ?? this.promptError,
      serviceError: clearServiceError
          ? null
          : serviceError ?? this.serviceError,
      authError: clearAuthError ? null : authError ?? this.authError,
      catalogError: clearCatalogError
          ? null
          : catalogError ?? this.catalogError,
      powerError: clearPowerError ? null : powerError ?? this.powerError,
      powerMode: powerMode ?? this.powerMode,
      backendAuthState: backendAuthState ?? this.backendAuthState,
      dormant: dormant ?? this.dormant,
    );
  }
}
