import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'greeter_host.dart';

class GreeterThemeContext {
  const GreeterThemeContext({required this.host, required this.tokens});

  final GreeterHost host;
  final ThemeTokens tokens;
}

abstract interface class GreeterThemeComponents {
  Widget build(BuildContext context, SceneNode node);
}

typedef GreeterThemeComponentsFactory = GreeterThemeComponents Function(
  GreeterThemeContext context,
);
