import 'package:flutter/widgets.dart';
import 'package:theme_sdk/theme_sdk.dart';

enum StudioPreviewScenario {
  password('Password'),
  username('Username'),
  submitting('Signing in'),
  rejectedPassword('Wrong password'),
  error('Authentication error'),
  userSelection('Choose account'),
  sessionSelection('Choose session'),
  starting('Connecting'),
  unavailable('Service unavailable');

  const StudioPreviewScenario(this.label);
  final String label;
}

/// Owns the simulated greeter inputs for one preview session. Theme components
/// borrow these resources, exactly as they borrow the production host's inputs.
class StudioPreviewHost {
  StudioPreviewHost({
    StudioPreviewScenario scenario = StudioPreviewScenario.password,
  }) {
    updateScenario(scenario);
  }

  static const _user = UserSummary(id: 'alice', displayName: 'Alice');
  static const _users = [_user, UserSummary(id: 'bob', displayName: 'Bob')];
  static const _sessions = [
    (id: 'wayland:sway', name: 'Sway'),
    (id: 'wayland:plasma', name: 'Plasma'),
  ];
  final _service = ValueNotifier<ServiceSlots>((
    mode: ServiceMode.starting,
    error: null,
  ));
  final _auth = ValueNotifier<AuthPromptSlots>((
    mode: AuthMode.userSelection,
    selectedUser: null,
    prompt: null,
    error: null,
    promptError: null,
  ));
  final _account = ValueNotifier(AccountPickerSlots(users: [], selected: null));
  final _session = ValueNotifier(
    SessionPickerSlots(
      mode: CatalogMode.empty,
      sessions: const [],
      selected: null,
      error: null,
    ),
  );
  final _power = ValueNotifier<PowerSlots>((mode: PowerMode.idle, error: null));
  final _credential = TextEditingController();
  final _focus = FocusNode();
  late final host = GreeterHost(
    serviceSlots: _service,
    authPromptSlots: _auth,
    accountPickerSlots: _account,
    sessionPickerSlots: _session,
    powerSlots: _power,
    credentialController: _credential,
    credentialFocusNode: _focus,
    onSelectUser: (_) {},
    onSelectSession: (_) {},
    onRequestPowerAction: (_) {},
    onRetry: (_) {},
    onRetrySessionCatalog: () {},
    onRespondToPrompt: () {},
    onStartSession: () {},
  );

  /// Changes only simulated inputs. Controllers and listenables retain their
  /// ownership across scenario and theme changes, as in the production host.
  void updateScenario(StudioPreviewScenario scenario) {
    final selectingUser =
        scenario == StudioPreviewScenario.userSelection ||
        scenario == StudioPreviewScenario.username ||
        scenario == StudioPreviewScenario.starting ||
        scenario == StudioPreviewScenario.unavailable;
    final user = selectingUser ? null : _user;
    _credential.clear();
    _service.value = switch (scenario) {
      StudioPreviewScenario.starting => (
        mode: ServiceMode.starting,
        error: null,
      ),
      StudioPreviewScenario.unavailable => (
        mode: ServiceMode.unavailable,
        error: (
          kind: GreeterErrorKind.transport,
          message: 'Greeter service unavailable.',
          recovery: GreeterRecovery.reconnectService,
        ),
      ),
      _ => (mode: ServiceMode.ready, error: null),
    };
    final mode = switch (scenario) {
      StudioPreviewScenario.submitting => AuthMode.submitting,
      StudioPreviewScenario.error => AuthMode.error,
      StudioPreviewScenario.sessionSelection => AuthMode.sessionSelection,
      StudioPreviewScenario.userSelection ||
      StudioPreviewScenario.starting ||
      StudioPreviewScenario.unavailable => AuthMode.userSelection,
      _ => AuthMode.prompting,
    };
    _auth.value = (
      mode: mode,
      selectedUser: user,
      prompt: mode == AuthMode.prompting || mode == AuthMode.submitting
          ? (
              kind: scenario == StudioPreviewScenario.username
                  ? PromptKind.visible
                  : PromptKind.secret,
              text: scenario == StudioPreviewScenario.username
                  ? 'Username'
                  : 'Password',
            )
          : null,
      error: scenario == StudioPreviewScenario.error
          ? (
              kind: GreeterErrorKind.authentication,
              message: 'Authentication failed. Please try again.',
              recovery: GreeterRecovery.retryAuthentication,
            )
          : null,
      promptError: scenario == StudioPreviewScenario.rejectedPassword
          ? 'Incorrect password. Please try again.'
          : null,
    );
    _account.value = AccountPickerSlots(
      users: _users,
      selected: user,
      canSelect: mode != AuthMode.submitting,
    );
    _session.value = SessionPickerSlots(
      mode: CatalogMode.ready,
      sessions: _sessions,
      selected: _sessions.first,
      error: null,
    );
  }

  void dispose() {
    _service.dispose();
    _auth.dispose();
    _account.dispose();
    _session.dispose();
    _power.dispose();
    _credential.dispose();
    _focus.dispose();
  }
}
