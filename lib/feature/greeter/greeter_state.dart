enum ServiceMode { starting, ready, unavailable }

enum CatalogMode { empty, loading, ready, failed }

enum AuthMode {
  userSelection,
  prompting,
  submitting,
  sessionSelection,
  handingOff,
  error,
}

enum PromptKind { visible, secret, info, error }

enum PowerMode { idle, executing, succeeded, failed }

enum PowerAction { powerOff, reboot, suspend, hibernate }

enum GreeterErrorKind {
  input,
  authentication,
  transport,
  session,
  power,
  visual,
}

enum GreeterRecovery {
  retryAuthentication,
  retryPrompt,
  reconnectService,
  retrySessionCatalog,
  selectUser,
  selectSession,
}

class GreeterError {
  const GreeterError({
    required this.kind,
    required this.message,
    required this.recovery,
  });

  final GreeterErrorKind kind;
  final String message;
  final GreeterRecovery recovery;

  @override
  bool operator ==(Object other) {
    return other is GreeterError &&
        other.kind == kind &&
        other.message == message &&
        other.recovery == recovery;
  }

  @override
  int get hashCode => Object.hash(kind, message, recovery);
}

class UserSummary {
  const UserSummary({
    required this.id,
    required this.displayName,
    this.iconPath = '',
  });

  final String id;
  final String displayName;

  /// Absolute icon file path from AccountsService, or empty when unavailable.
  final String iconPath;

  @override
  bool operator ==(Object other) {
    return other is UserSummary &&
        other.id == id &&
        other.displayName == displayName &&
        other.iconPath == iconPath;
  }

  @override
  int get hashCode => Object.hash(id, displayName, iconPath);
}

class SessionSummary {
  const SessionSummary({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) {
    return other is SessionSummary && other.id == id && other.name == name;
  }

  @override
  int get hashCode => Object.hash(id, name);
}

class PromptState {
  const PromptState({required this.kind, required this.text});

  final PromptKind kind;
  final String text;

  @override
  bool operator ==(Object other) {
    return other is PromptState && other.kind == kind && other.text == text;
  }

  @override
  int get hashCode => Object.hash(kind, text);
}

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
