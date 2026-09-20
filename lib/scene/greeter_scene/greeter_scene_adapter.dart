import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mozais_scene/mozais_scene.dart';

import '../../feature/greeter/greeter_commands.dart';
import '../../feature/greeter/greeter_effect.dart';
import '../../feature/greeter/greeter_feature.dart';
import '../../feature/greeter/greeter_state.dart';
import 'greeter_widget_catalog.dart';

class GreeterSceneAdapter extends StatefulWidget {
  const GreeterSceneAdapter({
    required this.feature,
    required this.theme,
    super.key,
  });

  final GreeterFeature feature;
  final ThemeBundle theme;

  @override
  State<GreeterSceneAdapter> createState() => _GreeterSceneAdapterState();
}

class _GreeterSceneAdapterState extends State<GreeterSceneAdapter>
    with SingleTickerProviderStateMixin {
  final TextEditingController _credentialController = TextEditingController();
  final FocusNode _credentialFocusNode = FocusNode();
  final List<String> _typeahead = <String>[];
  late final StreamSubscription<FeatureEffect> _effectSubscription;
  late final AnimationController _blurController;
  late Animation<double> _blurAnimation;
  late GreeterWidgetCatalog _catalog;

  @override
  void initState() {
    super.initState();
    _catalog = _createCatalog();
    _effectSubscription = widget.feature.effects.listen(_handleEffect);
    _blurController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: widget.feature.dormantSlots.value ? 0 : 1,
    );
    _blurAnimation = _createBlurAnimation();
    widget.feature.dormantSlots.addListener(_handleDormantChanged);
  }

  @override
  void didUpdateWidget(GreeterSceneAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.theme != oldWidget.theme) {
      _catalog = _createCatalog();
      _blurAnimation = _createBlurAnimation();
    }
  }

  GreeterWidgetCatalog _createCatalog() {
    return GreeterWidgetCatalog(
      feature: widget.feature,
      theme: widget.theme,
      credentialController: _credentialController,
      credentialFocusNode: _credentialFocusNode,
      onDispatch: _dispatch,
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
    widget.feature.dormantSlots.removeListener(_handleDormantChanged);
    unawaited(_effectSubscription.cancel());
    _blurController.dispose();
    _credentialController.dispose();
    _credentialFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.feature.dormantSlots,
        builder: (context, dormant, child) {
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: dormant
                ? (_) => _dispatch(const WakeGreeterCommand())
                : null,
            child: SceneRuntime(
              document: widget.theme.document,
              theme: widget.theme,
              backgroundBlurSigma: _blurAnimation,
              nodeBuilder: (context, node) =>
                  _catalog.build(context, node, dormant: dormant),
            ),
          );
        },
      ),
    );
  }

  void _handleDormantChanged() {
    if (widget.feature.dormantSlots.value) {
      _blurController.reverse();
    } else {
      _blurController.forward();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (widget.feature.dormantSlots.value) {
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
    if (_isCapturingTypeahead() && !_credentialFocusNode.hasFocus) {
      if (!_bufferKey(event)) {
        return KeyEventResult.ignored;
      }
      if (widget.feature.authPromptSlots.value.mode == AuthMode.prompting) {
        _scheduleFlushAndFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Buffers keystrokes typed before the credential field can take focus so
  /// the first characters of a password are not dropped during the wake.
  bool _isCapturingTypeahead() {
    final auth = widget.feature.authPromptSlots.value;
    if (auth.mode == AuthMode.prompting) {
      return !_credentialFocusNode.hasFocus;
    }
    // While the first prompt is still on its way the field is disabled, so
    // keep collecting; once a prompt exists the response is already in flight.
    return auth.mode == AuthMode.userSelection ||
        (auth.mode == AuthMode.submitting && auth.prompt == null);
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

  void _scheduleFlushAndFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _flushTypeahead();
      _credentialFocusNode.requestFocus();
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
          _scheduleFlushAndFocus();
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
