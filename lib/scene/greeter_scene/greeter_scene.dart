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
import '../scene_host.dart';

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
    return Scaffold(
      body: SceneHost(
        background: SceneRegion<BackgroundSlots>(
          valueListenable: widget.feature.backgroundSlots,
          repaintBoundary: true,
          builder: (context, background) {
            return StaticBackgroundVisual(slots: background);
          },
        ),
        overlay: SafeArea(
          child: SceneRegion<PowerSlots>(
            valueListenable: widget.feature.powerSlots,
            repaintBoundary: true,
            builder: (context, power) {
              return _TopBar(
                power: power,
                onPowerAction: (action) {
                  _dispatch(RequestPowerActionCommand(action));
                },
              );
            },
          ),
        ),
        content: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 72),
              Expanded(
                child: _SceneViewport(
                  feature: widget.feature,
                  theme: widget.theme,
                  credentialController: _credentialController,
                  credentialFocusNode: _credentialFocusNode,
                  onRespond: _respondToPrompt,
                  onDispatch: _dispatch,
                ),
              ),
            ],
          ),
        ),
      ),
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

class _SceneViewport extends StatelessWidget {
  const _SceneViewport({
    required this.feature,
    required this.theme,
    required this.credentialController,
    required this.credentialFocusNode,
    required this.onRespond,
    required this.onDispatch,
  });

  final GreeterFeature feature;
  final ThemeTokens theme;
  final TextEditingController credentialController;
  final FocusNode credentialFocusNode;
  final VoidCallback onRespond;
  final ValueChanged<GreeterCommand> onDispatch;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final content = RepaintBoundary(
          child: _ServiceRegion(
            feature: feature,
            theme: theme,
            credentialController: credentialController,
            credentialFocusNode: credentialFocusNode,
            onRespond: onRespond,
            onDispatch: onDispatch,
          ),
        );
        return SingleChildScrollView(
          padding: theme.pagePadding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - theme.pagePadding.vertical,
            ),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(child: _SceneBranding()),
                      SizedBox(width: theme.contentMaxWidth, child: content),
                    ],
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: theme.contentMaxWidth,
                      ),
                      child: content,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.power, required this.onPowerAction});

  final PowerSlots power;
  final ValueChanged<PowerAction> onPowerAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'MOZAIS',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 2.4),
          ),
          PopupMenuButton<PowerAction>(
            enabled: power.mode != PowerMode.executing,
            tooltip: 'Power actions',
            icon: power.mode == PowerMode.executing
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
        ],
      ),
    );
  }
}

class _SceneBranding extends StatelessWidget {
  const _SceneBranding();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 72),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WELCOME BACK',
            style: textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'MOZAIS',
            style: textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceRegion extends StatelessWidget {
  const _ServiceRegion({
    required this.feature,
    required this.theme,
    required this.credentialController,
    required this.credentialFocusNode,
    required this.onRespond,
    required this.onDispatch,
  });

  final GreeterFeature feature;
  final ThemeTokens theme;
  final TextEditingController credentialController;
  final FocusNode credentialFocusNode;
  final VoidCallback onRespond;
  final ValueChanged<GreeterCommand> onDispatch;

  @override
  Widget build(BuildContext context) {
    return SceneRegion<ServiceSlots>(
      valueListenable: feature.serviceSlots,
      builder: (context, service) {
        return _Panel(
          radius: theme.panelRadius,
          padding: theme.panelPadding,
          child: switch (service.mode) {
            ServiceMode.starting => const _StatusPanel(
              message: 'Loading greeter service...',
            ),
            ServiceMode.unavailable => _ErrorPanel(
              message:
                  service.error?.message ?? 'Greeter service is unavailable.',
              onRetry: () {
                onDispatch(const ReconnectServiceCommand());
              },
            ),
            ServiceMode.ready => _AuthRegion(
              feature: feature,
              theme: theme,
              credentialController: credentialController,
              credentialFocusNode: credentialFocusNode,
              onRespond: onRespond,
              onDispatch: onDispatch,
            ),
          },
        );
      },
    );
  }
}

class _AuthRegion extends StatelessWidget {
  const _AuthRegion({
    required this.feature,
    required this.theme,
    required this.credentialController,
    required this.credentialFocusNode,
    required this.onRespond,
    required this.onDispatch,
  });

  final GreeterFeature feature;
  final ThemeTokens theme;
  final TextEditingController credentialController;
  final FocusNode credentialFocusNode;
  final VoidCallback onRespond;
  final ValueChanged<GreeterCommand> onDispatch;

  @override
  Widget build(BuildContext context) {
    return SceneRegion<AuthPromptSlots>(
      valueListenable: feature.authPromptSlots,
      builder: (context, auth) {
        final content = switch (auth.mode) {
          AuthMode.userSelection => _SelectionStage(
            key: const ValueKey(AuthMode.userSelection),
            feature: feature,
            theme: theme,
            onDispatch: onDispatch,
          ),
          AuthMode.prompting => _PromptForm(
            key: const ValueKey(AuthMode.prompting),
            user: auth.selectedUser,
            prompt: auth.prompt!,
            controller: credentialController,
            focusNode: credentialFocusNode,
            controlHeight: theme.controlHeight,
            buttonGap: theme.controlGap,
            sectionGap: theme.sectionGap,
            actionGap: theme.promptActionGap,
            onSubmit: onRespond,
            onCancel: () {
              onDispatch(const CancelAuthenticationCommand());
            },
          ),
          AuthMode.submitting => const _StatusPanel(
            key: ValueKey(AuthMode.submitting),
            message: 'Working...',
          ),
          AuthMode.sessionSelection => _SessionSelectionRegion(
            key: const ValueKey(AuthMode.sessionSelection),
            feature: feature,
            theme: theme,
            onDispatch: onDispatch,
          ),
          AuthMode.handingOff => const _StatusPanel(
            key: ValueKey(AuthMode.handingOff),
            message: 'Starting session...',
          ),
          AuthMode.error => _ErrorPanel(
            key: const ValueKey(AuthMode.error),
            message: auth.error?.message ?? 'Authentication failed.',
            onRetry: switch (auth.error?.recovery) {
              GreeterRecovery.retryPrompt => () {
                onDispatch(const RetryPromptCommand());
              },
              GreeterRecovery.reconnectService => () {
                onDispatch(const ReconnectServiceCommand());
              },
              GreeterRecovery.selectSession => () {
                onDispatch(const CancelAuthenticationCommand());
              },
              _ => () {
                onDispatch(const RetryAuthenticationCommand());
              },
            },
          ),
        };
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: content,
        );
      },
    );
  }
}

class _SessionSelectionRegion extends StatelessWidget {
  const _SessionSelectionRegion({
    required super.key,
    required this.feature,
    required this.theme,
    required this.onDispatch,
  });

  final GreeterFeature feature;
  final ThemeTokens theme;
  final ValueChanged<GreeterCommand> onDispatch;

  @override
  Widget build(BuildContext context) {
    return SceneRegion<SessionPickerSlots>(
      valueListenable: feature.sessionPickerSlots,
      builder: (context, session) {
        return _SessionSelection(
          sessions: session.sessions,
          catalogMode: session.mode,
          catalogError: session.error,
          selected: session.selected,
          controlHeight: theme.controlHeight,
          itemGap: theme.controlGap,
          sectionGap: theme.sectionGap,
          onSelect: (value) {
            onDispatch(SelectSessionCommand(value));
          },
          onStart: () {
            onDispatch(const StartSelectedSessionCommand());
          },
          onCancel: () {
            onDispatch(const CancelAuthenticationCommand());
          },
          onRetry: () {
            onDispatch(const RetrySessionCatalogCommand());
          },
        );
      },
    );
  }
}

class _SelectionStage extends StatelessWidget {
  const _SelectionStage({
    required super.key,
    required this.feature,
    required this.theme,
    required this.onDispatch,
  });

  final GreeterFeature feature;
  final ThemeTokens theme;
  final ValueChanged<GreeterCommand> onDispatch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SceneRegion<AccountPickerSlots>(
          valueListenable: feature.accountPickerSlots,
          builder: (context, account) {
            return _UserSelection(
              users: account.users,
              selected: account.selected,
              controlHeight: theme.controlHeight,
              itemGap: theme.controlGap,
              sectionGap: theme.sectionGap,
              onSelect: (user) {
                onDispatch(SelectUserCommand(user));
              },
            );
          },
        ),
        SizedBox(height: theme.sectionGap),
        const Divider(),
        SizedBox(height: theme.sectionGap),
        Text(
          'Choose session',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Select the desktop session to start.'),
        SizedBox(height: theme.sectionGap),
        SceneRegion<SessionPickerSlots>(
          valueListenable: feature.sessionPickerSlots,
          builder: (context, session) {
            return _SessionOptions(
              sessions: session.sessions,
              catalogMode: session.mode,
              catalogError: session.error,
              selected: session.selected,
              controlHeight: theme.controlHeight,
              itemGap: theme.controlGap,
              onSelect: (value) {
                onDispatch(SelectSessionCommand(value));
              },
              onRetry: () {
                onDispatch(const RetrySessionCatalogCommand());
              },
            );
          },
        ),
        const SizedBox(height: 16),
        SceneRegion<ContinueSlots>(
          valueListenable: feature.continueSlots,
          builder: (context, action) {
            return SizedBox(
              height: theme.controlHeight,
              child: FilledButton.icon(
                onPressed: action.enabled
                    ? () => onDispatch(const BeginAuthenticationCommand())
                    : null,
                icon: const Icon(Icons.lock_open),
                label: const Text('Continue'),
              ),
            );
          },
        ),
      ],
    );
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
    final borderRadius = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.84),
          borderRadius: borderRadius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _UserSelection extends StatelessWidget {
  const _UserSelection({
    required this.users,
    required this.selected,
    required this.controlHeight,
    required this.itemGap,
    required this.sectionGap,
    required this.onSelect,
  });

  final List<UserSummary> users;
  final UserSummary? selected;
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
              icon: Icon(
                selected?.id == user.id
                    ? Icons.radio_button_checked
                    : Icons.person_outline,
              ),
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
        _SessionOptions(
          sessions: sessions,
          catalogMode: catalogMode,
          catalogError: catalogError,
          selected: selected,
          controlHeight: controlHeight,
          itemGap: itemGap,
          onSelect: onSelect,
          onRetry: onRetry,
        ),
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

class _SessionOptions extends StatelessWidget {
  const _SessionOptions({
    required this.sessions,
    required this.catalogMode,
    required this.catalogError,
    required this.selected,
    required this.controlHeight,
    required this.itemGap,
    required this.onSelect,
    required this.onRetry,
  });

  final List<SessionSummary> sessions;
  final CatalogMode catalogMode;
  final GreeterError? catalogError;
  final SessionSummary? selected;
  final double controlHeight;
  final double itemGap;
  final ValueChanged<SessionSummary> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (catalogMode) {
      CatalogMode.loading => const _StatusPanel(message: 'Loading sessions...'),
      CatalogMode.failed => _ErrorPanel(
        message: catalogError?.message ?? 'Sessions are unavailable.',
        onRetry: onRetry,
      ),
      CatalogMode.empty when sessions.isEmpty => const Text(
        'No desktop sessions are available.',
      ),
      CatalogMode.ready || CatalogMode.empty => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
      ),
    };
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
