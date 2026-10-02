import 'dart:async';

import 'package:flutter/material.dart';
import 'package:greeter_ui/greeter_ui.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../infrastructure/dbus/greeter_dbus_gateway.dart';

class MyApp extends StatefulWidget {
  const MyApp({
    required this.themeBuilder,
    this.sessionStore = const NoopSessionStore(),
    super.key,
  });

  final ThemeBuilder themeBuilder;

  /// Persistence for the selected session; the default keeps tests isolated.
  final SessionStore sessionStore;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GreeterFeature _feature;
  late ThemeDefinition _theme;
  Color? _themeSeed;

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
    _theme = widget.themeBuilder();
    unawaited(_loadThemeSeed());
    unawaited(_feature.initialize());
  }

  Future<void> _loadThemeSeed() async {
    final theme = _theme;
    final seed = await theme.findBackgroundSeed();
    if (!mounted || !identical(theme, _theme) || seed == null) {
      return;
    }
    setState(() {
      _themeSeed = seed;
      _theme = widget.themeBuilder(seed: seed);
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload preserves initState and authentication state. Recreate only
    // the theme so changed builders and generated scene getters take effect.
    _theme = widget.themeBuilder(seed: _themeSeed);
    unawaited(_loadThemeSeed());
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
