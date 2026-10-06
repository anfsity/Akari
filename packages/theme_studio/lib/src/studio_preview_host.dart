import 'package:flutter/widgets.dart';
import 'package:theme_sdk/theme_sdk.dart';

/// Owns the simulated greeter inputs for one preview session. Theme components
/// borrow these resources, exactly as they borrow the production host's inputs.
class StudioPreviewHost {
  static const _user = UserSummary(id: 'alice', displayName: 'Alice');
  final _service = ValueNotifier<ServiceSlots>((
    mode: ServiceMode.ready,
    error: null,
  ));
  final _auth = ValueNotifier<AuthPromptSlots>((
    mode: AuthMode.prompting,
    selectedUser: _user,
    prompt: (kind: PromptKind.secret, text: 'Password'),
    error: null,
    promptError: null,
  ));
  final _account = ValueNotifier(
    AccountPickerSlots(users: [_user], selected: _user),
  );
  final _session = ValueNotifier(
    SessionPickerSlots(
      mode: CatalogMode.ready,
      sessions: const [(id: 'wayland:sway', name: 'Sway')],
      selected: (id: 'wayland:sway', name: 'Sway'),
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
