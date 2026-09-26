import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mozais_greeter_ui/mozais_greeter_ui.dart';
import 'package:mozais_theme_catalog/mozais_theme_catalog.dart';

import '../infrastructure/dbus/greeter_dbus_gateway.dart';

class MyApp extends StatefulWidget {
  const MyApp({this.sessionStore = const NoopSessionStore(), super.key});

  /// Persistence for the selected session; the default keeps tests isolated.
  final SessionStore sessionStore;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GreeterFeature _feature;
  late ThemeDefinition _theme;

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
    _feature = GreeterFeature(
      gateway: gateway,
      sessionStore: widget.sessionStore,
    );
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
