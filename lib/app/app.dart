import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import '../feature/greeter/greeter_feature.dart';
import '../feature/greeter/ports/greeter_gateway.dart';
import '../infrastructure/dbus/greeter_dbus_gateway.dart';
import '../scene/greeter_scene/greeter_scene_adapter.dart';
import '../theme/theme_registry.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GreeterFeature _feature;
  late ThemeBundle _theme;

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
    final themeName = const String.fromEnvironment(
      'MOZAIS_THEME',
      defaultValue: ThemeRegistry.defaultThemeName,
    );
    _theme = ThemeRegistry.resolve(themeName);
    unawaited(_loadThemeSeed(themeName));
    unawaited(_feature.initialize());
  }

  Future<void> _loadThemeSeed(String themeName) async {
    final seed = await ThemeRegistry.findBackgroundSeed(_theme);
    if (!mounted || seed == null) {
      return;
    }
    setState(() {
      _theme = ThemeRegistry.resolve(themeName, seed: seed);
    });
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
      home: Scaffold(
        body: GreeterSceneAdapter(feature: _feature, theme: _theme),
      ),
    );
  }
}
