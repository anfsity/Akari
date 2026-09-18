import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mozais_scene/mozais_scene.dart';

import '../../feature/greeter/greeter_commands.dart';
import '../../feature/greeter/greeter_effect.dart';
import '../../feature/greeter/greeter_feature.dart';
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

class _GreeterSceneAdapterState extends State<GreeterSceneAdapter> {
  final TextEditingController _credentialController = TextEditingController();
  final FocusNode _credentialFocusNode = FocusNode();
  late final StreamSubscription<FeatureEffect> _effectSubscription;
  late final GreeterWidgetCatalog _catalog;

  @override
  void initState() {
    super.initState();
    _catalog = GreeterWidgetCatalog(
      feature: widget.feature,
      theme: widget.theme,
      credentialController: _credentialController,
      credentialFocusNode: _credentialFocusNode,
      onDispatch: _dispatch,
      onRespond: _respondToPrompt,
    );
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
    return SceneRuntime(
      document: widget.theme.document,
      theme: widget.theme,
      nodeBuilder: _catalog.build,
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
