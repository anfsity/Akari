/// Persists the session the user selected last.
abstract interface class SessionStore {
  Future<String?> readSelectedSessionId();

  Future<void> saveSelectedSessionId(String sessionId);
}

/// Store used by tests and hosts without a writable state directory.
class NoopSessionStore implements SessionStore {
  const NoopSessionStore();

  @override
  Future<String?> readSelectedSessionId() async => null;

  @override
  Future<void> saveSelectedSessionId(String sessionId) async {}
}
