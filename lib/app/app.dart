import 'dart:async';

import 'package:flutter/material.dart';

import '../feature/greeter/greeter_feature.dart';
import '../feature/greeter/ports/greeter_gateway.dart';
import '../infrastructure/dbus/greeter_dbus_gateway.dart';
import '../scene/greeter_scene/greeter_scene.dart';
import '../theme/theme_tokens.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GreeterFeature _feature;
  late final ThemeTokens _theme;

  @override
  void initState() {
    super.initState();
    final backendMode = const String.fromEnvironment(
      'MOZAIS_BACKEND',
      defaultValue: 'demo',
    );
    final gateway = backendMode == 'demo'
        ? DemoGreeterGateway()
        : DBusGreeterGateway();
    _feature = GreeterFeature(gateway: gateway);
    _theme = ThemeTokens.dark();
    unawaited(_feature.initialize());
  }

  @override
  void dispose() {
    _feature.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mozais Greeter',
      debugShowCheckedModeBanner: false,
      theme: _theme.materialTheme,
      home: GreeterScene(feature: _feature, theme: _theme),
    );
  }
}
