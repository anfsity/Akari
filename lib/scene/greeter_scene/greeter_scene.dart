import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../feature/greeter/greeter_commands.dart';
import '../../feature/greeter/greeter_effect.dart';
import '../../feature/greeter/greeter_feature.dart';
import '../../feature/greeter/greeter_slots.dart';
import '../../feature/greeter/greeter_state.dart';
import '../../theme/theme_tokens.dart';
import '../../visual/static_background.dart';

class GreeterScene extends StatefulWidget {
  const GreeterScene({required this.feature, required this.theme, super.key});

  final GreeterFeature feature;
  final ThemeTokens theme;

  @override
  State<GreeterScene> createState() => _GreeterSceneState();
}

class _GreeterSceneState extends State<GreeterScene> {
  final TextEditingController _credentialController = TextEditingController();
  final FocusNode _credentialFocusNode = FocusNode();
  late final StreamSubscription<FeatureEffect> _effectSubscription;

  @override
  void initState() {
    super.initState();
    _effectSubscription = widget.feature.effects.listen(_handleEffect);
  }

  @override
  void dispose() {
    unawaited(_effectSubscription.cancel());
    _credentialController.dispose();
    _credentialFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.feature,
      builder: (context, child) {
        final slots = widget.feature.slots;
        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: StaticBackgroundVisual(slots: slots.background),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(
                      powerMode: slots.power.mode,
                      onPowerAction: (action) {
                        _dispatch(RequestPowerActionCommand(action));
                      },
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: widget.theme.pagePadding,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: widget.theme.contentMaxWidth,
                            ),
                            child: _SceneContent(
                              slots: slots,
                              credentialController: _credentialController,
                              credentialFocusNode: _credentialFocusNode,
                              theme: widget.theme,
                              onSelectUser: (user) {
                                _dispatch(SelectUserCommand(user));
                              },
                              onBeginAuthentication: () {
                                _dispatch(const BeginAuthenticationCommand());
                              },
                              onRespond: _respondToPrompt,
                              onCancel: () {
                                _dispatch(const CancelAuthenticationCommand());
                              },
                              onSelectSession: (session) {
                                _dispatch(SelectSessionCommand(session));
                              },
                              onStartSession: () {
                                _dispatch(const StartSelectedSessionCommand());
                              },
                              onRetryService: () {
                                _dispatch(const ReconnectServiceCommand());
                              },
                              onRetryAuthentication: () {
                                _dispatch(const RetryAuthenticationCommand());
                              },
                              onRetryPrompt: () {
                                _dispatch(const RetryPromptCommand());
                              },
                              onRetrySessionCatalog: () {
                                _dispatch(const RetrySessionCatalogCommand());
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _respondToPrompt() {
    final response = _credentialController.text;
    _credentialController.clear();
    _dispatch(RespondToPromptCommand(response));
  }

  void _dispatch(GreeterCommand command) {
    unawaited(widget.feature.dispatch(command));
  }

  void _handleEffect(FeatureEffect effect) {
    switch (effect) {
      case RequestFocusEffect(:final field):
        if (field == 'credential') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _credentialFocusNode.requestFocus();
            }
          });
        }
      case ShowNoticeEffect(:final message, :final isError):
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: isError
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          );
        });
      case ExitAfterHandoffEffect():
        unawaited(SystemNavigator.pop());
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.powerMode, required this.onPowerAction});

  final PowerMode powerMode;
  final ValueChanged<PowerAction> onPowerAction;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: PopupMenuButton<PowerAction>(
          enabled: powerMode != PowerMode.executing,
          tooltip: 'Power actions',
          icon: powerMode == PowerMode.executing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.power_settings_new),
          onSelected: onPowerAction,
          itemBuilder: (context) => const [
            PopupMenuItem(value: PowerAction.suspend, child: Text('Suspend')),
            PopupMenuItem(value: PowerAction.reboot, child: Text('Reboot')),
            PopupMenuItem(
              value: PowerAction.powerOff,
              child: Text('Power off'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SceneContent extends StatelessWidget {
  const _SceneContent({
    required this.slots,
    required this.credentialController,
    required this.credentialFocusNode,
    required this.theme,
    required this.onSelectUser,
    required this.onBeginAuthentication,
    required this.onRespond,
    required this.onCancel,
    required this.onSelectSession,
    required this.onStartSession,
    required this.onRetryService,
    required this.onRetryAuthentication,
    required this.onRetryPrompt,
    required this.onRetrySessionCatalog,
  });

  final GreeterSceneSlots slots;
  final TextEditingController credentialController;
  final FocusNode credentialFocusNode;
  final ThemeTokens theme;
  final ValueChanged<UserSummary> onSelectUser;
  final VoidCallback onBeginAuthentication;
  final VoidCallback onRespond;
  final VoidCallback onCancel;
  final ValueChanged<SessionSummary> onSelectSession;
  final VoidCallback onStartSession;
  final VoidCallback onRetryService;
  final VoidCallback onRetryAuthentication;
  final VoidCallback onRetryPrompt;
  final VoidCallback onRetrySessionCatalog;

  @override
  Widget build(BuildContext context) {
    return switch (slots.service.mode) {
      ServiceMode.starting => _Panel(
        radius: theme.panelRadius,
        padding: theme.panelPadding,
        child: const _StatusPanel(message: 'Loading greeter service...'),
      ),
      ServiceMode.unavailable => _Panel(
        radius: theme.panelRadius,
        padding: theme.panelPadding,
        child: _ErrorPanel(
          message:
              slots.service.error?.message ?? 'Greeter service is unavailable.',
          onRetry: onRetryService,
        ),
      ),
      ServiceMode.ready => _Panel(
        radius: theme.panelRadius,
        padding: theme.panelPadding,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _buildAuthContent(context),
        ),
      ),
    };
  }

  Widget _buildAuthContent(BuildContext context) {
    return switch (slots.auth.mode) {
      AuthMode.userSelection => _UserSelection(
        key: const ValueKey(AuthMode.userSelection),
        users: slots.userPicker.users,
        controlHeight: theme.controlHeight,
        itemGap: theme.controlGap,
        sectionGap: theme.sectionGap,
        onSelect: onSelectUser,
      ),
      AuthMode.editing => _AuthenticationStart(
        key: const ValueKey(AuthMode.editing),
        user: slots.auth.selectedUser,
        controlHeight: theme.controlHeight,
        buttonGap: theme.controlGap,
        actionGap: theme.authenticationActionGap,
        onSubmit: onBeginAuthentication,
        onCancel: onCancel,
      ),
      AuthMode.prompting => _PromptForm(
        key: const ValueKey(AuthMode.prompting),
        user: slots.auth.selectedUser,
        prompt: slots.auth.prompt!,
        controller: credentialController,
        focusNode: credentialFocusNode,
        controlHeight: theme.controlHeight,
        buttonGap: theme.controlGap,
        sectionGap: theme.sectionGap,
        actionGap: theme.promptActionGap,
        onSubmit: onRespond,
        onCancel: onCancel,
      ),
      AuthMode.submitting => const _StatusPanel(
        key: ValueKey(AuthMode.submitting),
        message: 'Working...',
      ),
      AuthMode.sessionSelection => _SessionSelection(
        key: const ValueKey(AuthMode.sessionSelection),
        sessions: slots.sessionPicker.sessions,
        catalogMode: slots.sessionPicker.mode,
        catalogError: slots.sessionPicker.error,
        selected: slots.sessionPicker.selected,
        controlHeight: theme.controlHeight,
        itemGap: theme.controlGap,
        sectionGap: theme.sectionGap,
        onSelect: onSelectSession,
        onStart: onStartSession,
        onCancel: onCancel,
        onRetry: switch (slots.sessionPicker.error?.recovery) {
          GreeterRecovery.selectSession => onStartSession,
          _ => onRetrySessionCatalog,
        },
      ),
      AuthMode.handingOff => const _StatusPanel(
        key: ValueKey(AuthMode.handingOff),
        message: 'Starting session...',
      ),
      AuthMode.error => _ErrorPanel(
        key: const ValueKey(AuthMode.error),
        message: slots.auth.error?.message ?? 'Authentication failed.',
        onRetry: switch (slots.auth.error?.recovery) {
          GreeterRecovery.retryPrompt => onRetryPrompt,
          GreeterRecovery.reconnectService => onRetryService,
          _ => onRetryAuthentication,
        },
      ),
    };
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.radius,
    required this.padding,
    required this.child,
  });

  final double radius;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _UserSelection extends StatelessWidget {
  const _UserSelection({
    required super.key,
    required this.users,
    required this.controlHeight,
    required this.itemGap,
    required this.sectionGap,
    required this.onSelect,
  });

  final List<UserSummary> users;
  final double controlHeight;
  final double itemGap;
  final double sectionGap;
  final ValueChanged<UserSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose account',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Select an account to continue.'),
        SizedBox(height: sectionGap),
        for (final user in users) ...[
          SizedBox(
            height: controlHeight,
            child: OutlinedButton.icon(
              onPressed: () => onSelect(user),
              icon: const Icon(Icons.person_outline),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(user.displayName),
              ),
            ),
          ),
          SizedBox(height: itemGap),
        ],
      ],
    );
  }
}

class _AuthenticationStart extends StatelessWidget {
  const _AuthenticationStart({
    required super.key,
    required this.user,
    required this.controlHeight,
    required this.buttonGap,
    required this.actionGap,
    required this.onSubmit,
    required this.onCancel,
  });

  final UserSummary? user;
  final double controlHeight;
  final double buttonGap;
  final double actionGap;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AuthHeading(user: user),
        const Text('Continue to receive the authentication prompt.'),
        SizedBox(height: actionGap),
        _AuthActions(
          controlHeight: controlHeight,
          buttonGap: buttonGap,
          onCancel: onCancel,
          onContinue: onSubmit,
          continueIcon: Icons.lock_open,
        ),
      ],
    );
  }
}

class _PromptForm extends StatelessWidget {
  const _PromptForm({
    required super.key,
    required this.user,
    required this.prompt,
    required this.controller,
    required this.focusNode,
    required this.controlHeight,
    required this.buttonGap,
    required this.sectionGap,
    required this.actionGap,
    required this.onSubmit,
    required this.onCancel,
  });

  final UserSummary? user;
  final PromptState prompt;
  final TextEditingController controller;
  final FocusNode focusNode;
  final double controlHeight;
  final double buttonGap;
  final double sectionGap;
  final double actionGap;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isSecret = prompt.kind == PromptKind.secret;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AuthHeading(user: user),
        Text(prompt.text),
        SizedBox(height: sectionGap),
        TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          obscureText: isSecret,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            labelText: isSecret ? 'Password' : 'Response',
          ),
        ),
        SizedBox(height: actionGap),
        _AuthActions(
          controlHeight: controlHeight,
          buttonGap: buttonGap,
          onCancel: onCancel,
          onContinue: onSubmit,
          continueIcon: Icons.arrow_forward,
        ),
      ],
    );
  }
}

class _SessionSelection extends StatelessWidget {
  const _SessionSelection({
    required super.key,
    required this.sessions,
    required this.catalogMode,
    required this.catalogError,
    required this.selected,
    required this.controlHeight,
    required this.itemGap,
    required this.sectionGap,
    required this.onSelect,
    required this.onStart,
    required this.onCancel,
    required this.onRetry,
  });

  final List<SessionSummary> sessions;
  final CatalogMode catalogMode;
  final GreeterError? catalogError;
  final SessionSummary? selected;
  final double controlHeight;
  final double itemGap;
  final double sectionGap;
  final ValueChanged<SessionSummary> onSelect;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose session',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Select the desktop session to start.'),
        SizedBox(height: sectionGap),
        if (catalogMode == CatalogMode.loading)
          const _StatusPanel(message: 'Loading sessions...')
        else if (catalogMode == CatalogMode.failed)
          _ErrorPanel(
            message: catalogError?.message ?? 'Sessions are unavailable.',
            onRetry: onRetry,
          )
        else if (sessions.isEmpty)
          const Text('No desktop sessions are available.')
        else ...[
          for (final session in sessions) ...[
            SizedBox(
              height: controlHeight,
              child: OutlinedButton.icon(
                onPressed: () => onSelect(session),
                icon: Icon(
                  selected?.id == session.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(session.name),
                ),
              ),
            ),
            SizedBox(height: itemGap),
          ],
        ],
        const SizedBox(height: 8),
        SizedBox(
          height: controlHeight,
          child: FilledButton.icon(
            onPressed: selected == null ? null : onStart,
            icon: const Icon(Icons.login),
            label: const Text('Start session'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onCancel, child: const Text('Back')),
      ],
    );
  }
}

class _AuthHeading extends StatelessWidget {
  const _AuthHeading({required this.user});

  final UserSummary? user;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          user?.displayName ?? 'Authenticate',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _AuthActions extends StatelessWidget {
  const _AuthActions({
    required this.controlHeight,
    required this.buttonGap,
    required this.onCancel,
    required this.onContinue,
    required this.continueIcon,
  });

  final double controlHeight;
  final double buttonGap;
  final VoidCallback onCancel;
  final VoidCallback onContinue;
  final IconData continueIcon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: controlHeight,
            child: TextButton(onPressed: onCancel, child: const Text('Back')),
          ),
        ),
        SizedBox(width: buttonGap),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: controlHeight,
            child: FilledButton.icon(
              onPressed: onContinue,
              icon: Icon(continueIcon),
              label: const Text('Continue'),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(message),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline,
          size: 40,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
