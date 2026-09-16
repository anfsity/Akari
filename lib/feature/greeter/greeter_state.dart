enum ServiceMode { starting, ready, unavailable }

enum AuthMode {
  userSelection,
  editing,
  prompting,
  submitting,
  sessionSelection,
  handingOff,
  error,
}

enum PromptKind { visible, secret, info, error }

enum PowerMode { idle, executing, succeeded, failed }

enum PowerAction { powerOff, reboot, suspend, hibernate }

class UserSummary {
  const UserSummary({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

class SessionSummary {
  const SessionSummary({required this.id, required this.name});

  final String id;
  final String name;
}

class PromptState {
  const PromptState({required this.kind, required this.text});

  final PromptKind kind;
  final String text;
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
    required this.authMode,
    required List<UserSummary> users,
    required List<SessionSummary> sessions,
    required this.selectedUser,
    required this.selectedSession,
    required this.prompt,
    required this.error,
    required this.powerMode,
    required this.backendAuthState,
  }) : users = List.unmodifiable(users),
       sessions = List.unmodifiable(sessions);

  factory GreeterState.initial() {
    return GreeterState(
      serviceMode: ServiceMode.starting,
      authMode: AuthMode.userSelection,
      users: <UserSummary>[],
      sessions: <SessionSummary>[],
      selectedUser: null,
      selectedSession: null,
      prompt: null,
      error: null,
      powerMode: PowerMode.idle,
      backendAuthState: BackendAuthState.idle,
    );
  }

  final ServiceMode serviceMode;
  final AuthMode authMode;
  final List<UserSummary> users;
  final List<SessionSummary> sessions;
  final UserSummary? selectedUser;
  final SessionSummary? selectedSession;
  final PromptState? prompt;
  final String? error;
  final PowerMode powerMode;
  final BackendAuthState backendAuthState;

  GreeterState copyWith({
    ServiceMode? serviceMode,
    AuthMode? authMode,
    List<UserSummary>? users,
    List<SessionSummary>? sessions,
    UserSummary? selectedUser,
    bool clearSelectedUser = false,
    SessionSummary? selectedSession,
    bool clearSelectedSession = false,
    PromptState? prompt,
    bool clearPrompt = false,
    String? error,
    bool clearError = false,
    PowerMode? powerMode,
    BackendAuthState? backendAuthState,
  }) {
    return GreeterState(
      serviceMode: serviceMode ?? this.serviceMode,
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
      error: clearError ? null : error ?? this.error,
      powerMode: powerMode ?? this.powerMode,
      backendAuthState: backendAuthState ?? this.backendAuthState,
    );
  }
}
