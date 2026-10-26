import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scene/scene.dart';
import 'package:theme_sdk/theme_sdk.dart'
    show
        AccountPickerSlots,
        AuthMode,
        AuthPromptSlots,
        GreeterHost,
        PowerSlots,
        ServiceMode,
        ServiceSlots,
        SessionPickerSlots,
        SessionSummary,
        ThemeDefinition,
        UserSummary,
        getActiveScenePredicates;

import '../feature/greeter_commands.dart';
import '../feature/greeter_effect.dart';
import '../feature/greeter_feature.dart';

export 'package:theme_sdk/theme_sdk.dart' show getActiveScenePredicates;

/// Alias for backward compatibility with external callers.
Set<ScenePredicate> activeScenePredicates({
  required ServiceSlots service,
  required AuthPromptSlots auth,
  required AccountPickerSlots account,
  required SessionPickerSlots session,
  required PowerSlots power,
  required bool dormant,
}) => getActiveScenePredicates(
  service: service,
  auth: auth,
  account: account,
  session: session,
  power: power,
  dormant: dormant,
);

/// UI lifetime boundary between feature state and compiled theme components.
///
/// Owns per-display focus and wake animation, borrowing shared credential text
/// when displays mirror the application. The cached scene receives notifications
/// and local slot updates, avoiding a full scene rebuild for each backend event.
class GreeterSceneAdapter extends StatefulWidget {
  const GreeterSceneAdapter({
    required this.feature,
    required this.theme,
    this.credentialController,
    this.isActive = true,
    super.key,
  });

  final GreeterFeature feature;
  final ThemeDefinition theme;

  /// Multiple displays borrow one controller from the application owner.
  final TextEditingController? credentialController;
  final bool isActive;

  @override
  State<GreeterSceneAdapter> createState() => _GreeterSceneAdapterState();
}

class _GreeterSceneAdapterState extends State<GreeterSceneAdapter>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _credentialController;
  final FocusNode _credentialFocusNode = FocusNode();
  final List<String> _typeahead = <String>[];
  late StreamSubscription<FeatureEffect> _effectSubscription;
  late final AnimationController _wakeController;
  late Widget _scene;
  late final ValueNotifier<Set<ScenePredicate>> _activeScenePredicates;

  @override
  void initState() {
    super.initState();
    _credentialController =
        widget.credentialController ?? TextEditingController();
    _activeScenePredicates = ValueNotifier(_activePredicates());
    _startListeningToFeature(widget.feature);
    _wakeController = AnimationController(
      vsync: this,
      duration: Duration.zero,
      value: widget.feature.dormantSlots.value ? 0 : 1,
    );
    _scene = _createScene();
    // Key handling must not depend on the focus chain: the credential field
    // is disabled between attempts, which drops focus to the root scope.
    FocusManager.instance.addEarlyKeyEventHandler(_handleKeyEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateWakeDuration();
  }

  void _updateWakeDuration() {
    final disableAnimations =
        widget.theme.tokens.disableAnimations ||
        MediaQuery.disableAnimationsOf(context);
    _wakeController.duration = disableAnimations
        ? Duration.zero
        : widget.theme.tokens.mediumMotion;
    if (disableAnimations) {
      _wakeController.value = widget.feature.dormantSlots.value ? 0 : 1;
    }
  }

  @override
  void didUpdateWidget(GreeterSceneAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(widget.credentialController == oldWidget.credentialController);
    if (widget.isActive && !oldWidget.isActive) {
      _scheduleCredentialFocus();
    }
    final featureChanged = !identical(widget.feature, oldWidget.feature);
    if (featureChanged) {
      _stopListeningToFeature(oldWidget.feature);
      _startListeningToFeature(widget.feature);
      _resetCredentialInput();
      _wakeController.value = widget.feature.dormantSlots.value ? 0 : 1;
    }
    if (featureChanged || widget.theme != oldWidget.theme) {
      _updateWakeDuration();
      _activeScenePredicates.value = _activePredicates();
      _scene = _createScene();
    }
  }

  void _resetCredentialInput() {
    _credentialController.clear();
    _typeahead.clear();
    _credentialFocusNode.unfocus();
  }

  void _startListeningToFeature(GreeterFeature feature) {
    _effectSubscription = feature.effects.listen(
      (effect) => _handleEffect(feature, effect),
    );
    feature.slotChanges.addListener(_handleSceneSlotsChanged);
    feature.dormantSlots.addListener(_handleDormantChanged);
  }

  void _stopListeningToFeature(GreeterFeature feature) {
    feature.slotChanges.removeListener(_handleSceneSlotsChanged);
    feature.dormantSlots.removeListener(_handleDormantChanged);
    unawaited(_effectSubscription.cancel());
  }

  Widget _createScene() {
    return widget.theme.buildScene(
      host: GreeterHost(
        serviceSlots: widget.feature.serviceSlots,
        authPromptSlots: widget.feature.authPromptSlots,
        accountPickerSlots: widget.feature.accountPickerSlots,
        sessionPickerSlots: widget.feature.sessionPickerSlots,
        powerSlots: widget.feature.powerSlots,
        credentialController: _credentialController,
        credentialFocusNode: _credentialFocusNode,
        onSelectUser: _selectUser,
        onSelectSession: _selectSession,
        onRequestPowerAction: (action) =>
            _dispatch(RequestPowerActionCommand(action)),
        onRetry: (recovery) => _dispatch(getRecoveryCommand(recovery)),
        onRetrySessionCatalog: () =>
            _dispatch(const RetrySessionCatalogCommand()),
        onRespondToPrompt: _respondToPrompt,
        onStartSession: () => _dispatch(const StartSelectedSessionCommand()),
      ),
      activePredicates: _activeScenePredicates.value,
      activePredicatesListenable: _activeScenePredicates,
      wakeProgress: _wakeController,
    );
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKeyEvent);
    _stopListeningToFeature(widget.feature);
    _activeScenePredicates.dispose();
    _wakeController.dispose();
    if (widget.credentialController == null) {
      _credentialController.dispose();
    }
    _credentialFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.isActive,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (widget.feature.dormantSlots.value) {
            _dispatch(const WakeGreeterCommand());
          }
        },
        child: _scene,
      ),
    );
  }

  void _handleSceneSlotsChanged() {
    final nextPredicates = _activePredicates();
    if (setEquals(_activeScenePredicates.value, nextPredicates)) {
      return;
    }
    _activeScenePredicates.value = nextPredicates;
  }

  Set<ScenePredicate> _activePredicates() {
    return activeScenePredicates(
      service: widget.feature.serviceSlots.value,
      auth: widget.feature.authPromptSlots.value,
      account: widget.feature.accountPickerSlots.value,
      session: widget.feature.sessionPickerSlots.value,
      power: widget.feature.powerSlots.value,
      dormant: widget.feature.dormantSlots.value,
    );
  }

  void _handleDormantChanged() {
    if (widget.feature.dormantSlots.value) {
      // Authentication stays alive while hidden, but local credential text
      // must not remain in the field when the greeter returns to its background.
      _resetCredentialInput();
      _wakeController.reverse();
    } else {
      _wakeController.forward();
      _scheduleCredentialFocus();
    }
    _handleSceneSlotsChanged();
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (!widget.isActive || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    // A pushed dialog or menu owns the keyboard until it is dismissed.
    if (ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    if (widget.feature.dormantSlots.value) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        return KeyEventResult.ignored;
      }
      _dispatch(const WakeGreeterCommand());
      _bufferKey(event);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _typeahead.clear();
      _dispatch(const SleepGreeterCommand());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (widget.feature.authPromptSlots.value.mode == AuthMode.prompting) {
        _respondToPrompt();
        return KeyEventResult.handled;
      }
      if (widget.feature.authPromptSlots.value.mode ==
          AuthMode.sessionSelection) {
        _dispatch(const StartSelectedSessionCommand());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_credentialFocusNode.hasFocus || !_capturesTypeahead()) {
      return KeyEventResult.ignored;
    }
    if (!_bufferKey(event)) {
      return KeyEventResult.ignored;
    }
    _recoverPromptForTyping();
    return KeyEventResult.handled;
  }

  /// Whether a keystroke typed outside the credential field should be held
  /// until a prompt can accept it. A rejected response keeps the same attempt,
  /// so typing resumes it instead of waiting for the retry action.
  bool _capturesTypeahead() {
    if (widget.feature.serviceSlots.value.mode != ServiceMode.ready) {
      return false;
    }
    final auth = widget.feature.authPromptSlots.value;
    return auth.mode == AuthMode.prompting ||
        auth.mode == AuthMode.userSelection ||
        auth.mode == AuthMode.error ||
        (auth.mode == AuthMode.submitting && auth.prompt == null);
  }

  /// Makes the buffered keystroke land in the credential field, restarting a
  /// rejected prompt when the field is not currently accepting input.
  void _recoverPromptForTyping() {
    final auth = widget.feature.authPromptSlots.value;
    switch (auth.mode) {
      case AuthMode.prompting:
        _flushTypeaheadAndFocus();
      case AuthMode.error:
        _dispatch(getRecoveryCommand(auth.error!.recovery));
      case AuthMode.userSelection:
      case AuthMode.submitting:
      case AuthMode.sessionSelection:
      case AuthMode.handingOff:
        break;
    }
  }

  String? _findTypeaheadCharacter(KeyEvent event) {
    final character = event.character;
    if (character == null || character.length != 1) {
      return null;
    }
    final codeUnit = character.codeUnitAt(0);
    // Typeahead accepts printable ASCII only (0x21 '!' to 0x7e '~'). Space
    // (0x20) is excluded to avoid unintentional wake-to-credential leakage
    // since Space is also the primary wake shortcut. Input methods and
    // composed text belong to the native TextField once focused.
    if (codeUnit < 0x21 || codeUnit > 0x7e) {
      return null;
    }
    return character;
  }

  bool _bufferKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_typeahead.isNotEmpty) {
        _typeahead.removeLast();
      }
      return true;
    }
    final character = _findTypeaheadCharacter(event);
    if (character == null) {
      return false;
    }
    _typeahead.add(character);
    return true;
  }

  void _flushTypeaheadAndFocus() {
    if (!widget.isActive) {
      return;
    }
    _flushTypeahead();
    _credentialFocusNode.canRequestFocus = true;
    // An active ExcludeFocus higher in the tree (such as during wake animation
    // or when dialogs are pushed) can cause canRequestFocus to return false
    // immediately despite setting it. In that case, defer focus to post-frame.
    if (_credentialFocusNode.canRequestFocus) {
      _credentialFocusNode.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isActive) {
        _credentialFocusNode.requestFocus();
      }
    });
  }

  void _scheduleCredentialFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.isActive &&
          !widget.feature.dormantSlots.value &&
          widget.feature.authPromptSlots.value.mode == AuthMode.prompting) {
        _flushTypeaheadAndFocus();
      }
    });
  }

  void _flushTypeahead() {
    if (_typeahead.isEmpty) {
      return;
    }
    final text = _credentialController.text + _typeahead.join();
    _typeahead.clear();
    _credentialController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _respondToPrompt() {
    final response = _credentialController.text;
    // Clear before asynchronous dispatch so a pending request or failure does
    // not leave the submitted secret visible or available for a second submit.
    _credentialController.clear();
    _dispatch(RespondToPromptCommand(response));
  }

  void _selectUser(UserSummary user) {
    if (user.id != widget.feature.accountPickerSlots.value.selected?.id) {
      _resetCredentialInput();
    }
    _typeahead.clear();
    unawaited(widget.feature.dispatch(SelectUserCommand(user)));
  }

  void _selectSession(SessionSummary session) {
    _typeahead.clear();
    unawaited(widget.feature.dispatch(SelectSessionCommand(session)));
  }

  void _dispatch(GreeterCommand command) {
    unawaited(widget.feature.dispatch(command));
  }

  void _handleEffect(GreeterFeature source, FeatureEffect effect) {
    if (!mounted || !identical(widget.feature, source)) {
      return;
    }
    switch (effect) {
      case ClearCredentialEffect():
        _resetCredentialInput();
      case FocusCredentialEffect():
        _flushTypeaheadAndFocus();
      case ShowErrorNoticeEffect(:final message):
        // Slot listeners may emit effects during a widget update. Defer the
        // messenger mutation until build completes, then recheck its owner.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !identical(widget.feature, source)) {
            return;
          }
          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();
          messenger.removeCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        });
      case ExitAfterHandoffEffect():
        if (widget.isActive) {
          unawaited(SystemNavigator.pop());
        }
    }
  }
}
