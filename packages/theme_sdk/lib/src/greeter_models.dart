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

typedef GreeterError = ({
  GreeterErrorKind kind,
  String message,
  GreeterRecovery recovery,
});

class UserSummary {
  const UserSummary({
    required this.id,
    required this.displayName,
    this.iconPath = '',
  });

  final String id;
  final String displayName;
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

typedef SessionSummary = ({String id, String name});

typedef PromptState = ({PromptKind kind, String text});
