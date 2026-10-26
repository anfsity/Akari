/// Persists the session the user selected last.
abstract interface class SessionStore {
  Future<String?> findSelectedSessionId();

  Future<void> saveSelectedSessionId(String sessionId);
}

/// Store used by tests and hosts without a writable state directory.
class NoopSessionStore implements SessionStore {
  const NoopSessionStore();

  @override
  Future<String?> findSelectedSessionId() async => null;

  @override
  Future<void> saveSelectedSessionId(String sessionId) async {}
}
