import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mozais_scene/mozais_scene.dart';

import '../../feature/greeter/greeter_commands.dart';
import '../../feature/greeter/greeter_effect.dart';
import '../../feature/greeter/greeter_feature.dart';
import '../../feature/greeter/greeter_slots.dart';
import '../../feature/greeter/greeter_state.dart';
import 'greeter_widget_catalog.dart';

/// Maps the current greeter slots onto the scene predicate vocabulary.
Set<ScenePredicate> activeScenePredicates({
  required ServiceSlots service,
  required AuthPromptSlots auth,
  required AccountPickerSlots account,
  required SessionPickerSlots session,
  required PowerSlots power,
  required bool dormant,
}) {
  return <ScenePredicate>{
    if (dormant) ScenePredicate.isDormant,
    switch (service.mode) {
      ServiceMode.starting => ScenePredicate.isServiceStarting,
      ServiceMode.ready => ScenePredicate.isServiceReady,
      ServiceMode.unavailable => ScenePredicate.isServiceUnavailable,
    },
    switch (auth.mode) {
      AuthMode.userSelection => ScenePredicate.isUserSelection,
      AuthMode.prompting => ScenePredicate.isAuthPrompting,
      AuthMode.submitting => ScenePredicate.isAuthSubmitting,
      AuthMode.sessionSelection => ScenePredicate.isSessionSelection,
      AuthMode.handingOff => ScenePredicate.isHandingOff,
      AuthMode.error => ScenePredicate.isAuthError,
    },
    if (account.selected != null) ScenePredicate.hasSelectedUser,
    switch (session.mode) {
      CatalogMode.empty => ScenePredicate.isSessionEmpty,
      CatalogMode.loading => ScenePredicate.isSessionLoading,
      CatalogMode.ready => ScenePredicate.isSessionReady,
      CatalogMode.failed => ScenePredicate.isSessionFailed,
    },
    if (power.mode == PowerMode.executing) ScenePredicate.isPowerExecuting,
    if (power.error != null) ScenePredicate.hasPowerError,
  };
}

class GreeterSceneAdapter extends StatefulWidget {
  const GreeterSceneAdapter({
    required this.feature,
    required this.theme,
    this.handleKeyboard = true,
    super.key,
  });

  final GreeterFeature feature;
  final ThemeBundle theme;

  /// Whether the adapter installs the greeter's global key handling.
  ///
  /// A host that embeds the greeter beside its own text fields, such as the
  /// scene editor, sets this false so keystrokes are not captured.
  final bool handleKeyboard;

  @override
  State<GreeterSceneAdapter> createState() => _GreeterSceneAdapterState();
}

class _GreeterSceneAdapterState extends State<GreeterSceneAdapter>
    with SingleTickerProviderStateMixin {
  final TextEditingController _credentialController = TextEditingController();
  final FocusNode _credentialFocusNode = FocusNode();
  final List<String> _typeahead = <String>[];
  late final StreamSubscription<FeatureEffect> _effectSubscription;
  late final Listenable _featureSlotChanges;
  late final AnimationController _blurController;
  late Animation<double> _blurAnimation;
  late GreeterWidgetCatalog _catalog;
  late Widget _sceneRuntime;
  late final ValueNotifier<Set<ScenePredicate>> _activeScenePredicates;

  @override
  void initState() {
    super.initState();
    _catalog = _createCatalog();
    _activeScenePredicates = ValueNotifier(_activePredicates());
    _effectSubscription = widget.feature.effects.listen(_handleEffect);
    _featureSlotChanges = Listenable.merge([
      widget.feature.serviceSlots,
      widget.feature.authPromptSlots,
      widget.feature.accountPickerSlots,
      widget.feature.sessionPickerSlots,
      widget.feature.powerSlots,
    ])..addListener(_handleSceneSlotsChanged);
    _blurController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: widget.feature.dormantSlots.value ? 0 : 1,
    );
    _blurAnimation = _createBlurAnimation();
    _sceneRuntime = _createSceneRuntime();
    widget.feature.dormantSlots.addListener(_handleDormantChanged);
    // Key handling must not depend on the focus chain: the credential field
    // is disabled between attempts, which drops focus to the root scope.
    if (widget.handleKeyboard) {
      FocusManager.instance.addEarlyKeyEventHandler(_handleKeyEvent);
    }
  }

  @override
  void didUpdateWidget(GreeterSceneAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.handleKeyboard != oldWidget.handleKeyboard) {
      if (widget.handleKeyboard) {
        FocusManager.instance.addEarlyKeyEventHandler(_handleKeyEvent);
      } else {
        FocusManager.instance.removeEarlyKeyEventHandler(_handleKeyEvent);
      }
    }
    if (widget.theme != oldWidget.theme) {
      _catalog = _createCatalog();
      _blurAnimation = _createBlurAnimation();
      _activeScenePredicates.value = _activePredicates();
      _sceneRuntime = _createSceneRuntime();
    }
  }

  GreeterWidgetCatalog _createCatalog() {
    return GreeterWidgetCatalog(
      feature: widget.feature,
      theme: widget.theme,
      credentialController: _credentialController,
      credentialFocusNode: _credentialFocusNode,
      onDispatch: _dispatch,
      onRespond: _respondToPrompt,
    );
  }

  Widget _createSceneRuntime() {
    return SceneRuntime(
      document: widget.theme.document,
      theme: widget.theme,
      activePredicates: _activeScenePredicates.value,
      activePredicatesListenable: _activeScenePredicates,
      backgroundBlurSigma: _blurAnimation,
      prewarmHiddenNodes: true,
      nodeBuilder: _catalog.build,
    );
  }

  Animation<double> _createBlurAnimation() {
    return _blurController
        .drive(CurveTween(curve: Curves.easeOutCubic))
        .drive(
          Tween<double>(
            begin: 0,
            end: widget.theme.document.background.blurSigma,
          ),
        );
  }

  @override
  void dispose() {
    if (widget.handleKeyboard) {
      FocusManager.instance.removeEarlyKeyEventHandler(_handleKeyEvent);
    }
    _featureSlotChanges.removeListener(_handleSceneSlotsChanged);
    widget.feature.dormantSlots.removeListener(_handleDormantChanged);
    _activeScenePredicates.dispose();
    unawaited(_effectSubscription.cancel());
    _blurController.dispose();
    _credentialController.dispose();
    _credentialFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.handleKeyboard,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (widget.feature.dormantSlots.value) {
            _dispatch(const WakeGreeterCommand());
          }
        },
        child: _sceneRuntime,
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
      // The attempt is cancelled when the greeter sleeps, so discard the
      // response instead of retaining it in the field during the exit.
      _credentialController.clear();
      _typeahead.clear();
      _credentialFocusNode.unfocus();
      _blurController.reverse();
    } else {
      _blurController.forward();
    }
    _handleSceneSlotsChanged();
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
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
        final error = auth.error;
        if (error != null) {
          _dispatch(recoveryCommand(error.recovery));
        }
      case AuthMode.userSelection:
      case AuthMode.submitting:
      case AuthMode.sessionSelection:
      case AuthMode.handingOff:
        break;
    }
  }

  bool _bufferKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_typeahead.isNotEmpty) {
        _typeahead.removeLast();
      }
      return true;
    }
    final character = event.character;
    if (character == null || character.length != 1) {
      return false;
    }
    final codeUnit = character.codeUnitAt(0);
    if (codeUnit < 0x21 || codeUnit > 0x7e) {
      return false;
    }
    _typeahead.add(character);
    return true;
  }

  void _flushTypeaheadAndFocus() {
    _flushTypeahead();
    _credentialFocusNode.canRequestFocus = true;
    if (_credentialFocusNode.canRequestFocus) {
      _credentialFocusNode.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _credentialFocusNode.requestFocus();
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
    _credentialController.clear();
    _dispatch(RespondToPromptCommand(response));
  }

  void _dispatch(GreeterCommand command) {
    if (command is SelectUserCommand || command is SelectSessionCommand) {
      _typeahead.clear();
    }
    unawaited(widget.feature.dispatch(command));
  }

  void _handleEffect(FeatureEffect effect) {
    switch (effect) {
      case RequestFocusEffect(:final field):
        if (field == 'credential') {
          _flushTypeaheadAndFocus();
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
