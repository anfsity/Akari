import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

/// Renders the compiled theme at its authored resolution. Selection wraps each
/// component inside SceneRuntime so hit testing follows its actual transform,
/// paint order and visibility instead of a second approximation of layout.
class StudioPreview extends StatefulWidget {
  const StudioPreview({
    required this.theme,
    required this.document,
    required this.selectedId,
    required this.dormant,
    required this.onSelect,
    super.key,
  });

  final ThemeDefinition theme;
  final SceneDocument document;
  final String selectedId;
  final bool dormant;
  final ValueChanged<String> onSelect;

  @override
  State<StudioPreview> createState() => _StudioPreviewState();
}

class _StudioPreviewState extends State<StudioPreview> {
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
  late final _host = GreeterHost(
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
  );

  @override
  void dispose() {
    _service.dispose();
    _auth.dispose();
    _account.dispose();
    _session.dispose();
    _power.dispose();
    _credential.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final size = Size(
      document.canvas.referenceWidth.toDouble(),
      document.canvas.referenceHeight.toDouble(),
    );
    final components = widget.theme.components(
      GreeterThemeContext(host: _host, tokens: widget.theme.tokens),
    );
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox.fromSize(
          size: size,
          // Material belongs to the theme preview alone; the editor's controls
          // use shadcn. This also provides localization for theme components.
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: widget.theme.materialTheme,
            home: MediaQuery(
              data: MediaQueryData(size: size, disableAnimations: true),
              child: Scaffold(
                body: SceneRuntime(
                  document: document,
                  theme: widget.theme.bundle,
                  backgroundBlurSigma: AlwaysStoppedAnimation(
                    widget.dormant ? 0 : document.background.blurSigma,
                  ),
                  activePredicates: {
                    ScenePredicate.isServiceReady,
                    ScenePredicate.isAuthPrompting,
                    ScenePredicate.hasSelectedUser,
                    ScenePredicate.isSessionReady,
                    if (widget.dormant) ScenePredicate.isDormant,
                  },
                  nodeBuilder: (context, node) => GestureDetector(
                    key: ValueKey('preview-${node.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onSelect(node.id),
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: node.id == widget.selectedId
                            ? Border.all(
                                color: const Color(0xffa78bfa),
                                width: 3,
                              )
                            : null,
                      ),
                      child: ExcludeFocus(
                        child: IgnorePointer(
                          child: components.build(context, node),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
