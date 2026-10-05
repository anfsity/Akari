import 'package:flutter/material.dart';
import 'package:scene/scene.dart';

import 'greeter_host.dart';

/// Borrowed semantic host and visual tokens passed to a theme's factory.
///
/// The application owns the host's controllers and listenables. A component may
/// subscribe while mounted, but must not dispose those borrowed resources.
class GreeterThemeContext {
  const GreeterThemeContext({required this.host, required this.tokens});

  final GreeterHost host;
  final ThemeTokens tokens;
}

/// Resolves a theme's authored component identifiers into Flutter widgets.
///
/// Each factory owns its identifier vocabulary and property interpretation;
/// the scene runtime handles layout and presence around the returned widget.
abstract interface class GreeterThemeComponents {
  /// Builds [node]'s visual content within its runtime-managed layout region.
  ///
  /// Interactive components use host callbacks rather than accessing the
  /// authentication feature or transport directly.
  Widget build(BuildContext context, SceneNode node);
}

/// Creates a component set using the semantic host and tokens of one theme.
typedef GreeterThemeComponentsFactory = GreeterThemeComponents Function(
  GreeterThemeContext context,
);
