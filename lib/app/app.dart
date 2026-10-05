import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:greeter_ui/greeter_ui.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../infrastructure/dbus/greeter_dbus_gateway.dart';

/// Application lifetime owner of the feature and selected compiled theme.
/// The entrypoint injects the theme builder so preview and production use the
/// same host without discovering or loading theme code at runtime.
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

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static const _displayChannel = MethodChannel('akari/displays');
  final _credentialController = TextEditingController();
  late final GreeterFeature _feature;
  late ThemeDefinition _theme;
  late List<FlutterView> _views;
  late int _activeViewId;
  Color? _themeSeed;

  @override
  void initState() {
    super.initState();
    _views = WidgetsBinding.instance.platformDispatcher.views.toList();
    _activeViewId =
        WidgetsBinding.instance.platformDispatcher.implicitView!.viewId;
    WidgetsBinding.instance.addObserver(this);
    _displayChannel.setMethodCallHandler((call) async {
      if (call.method == 'focusView') {
        _activateView(call.arguments as int);
      }
    });
    final backendMode = const String.fromEnvironment(
      'AKARI_BACKEND',
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
    // A hot reload can replace the theme while asset decoding is pending.
    // Applying that old seed would overwrite the newly assembled theme.
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
  void didChangeMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views.toList();
    if (views.length == _views.length &&
        views.every((view) => _views.any((old) => old.viewId == view.viewId))) {
      return;
    }
    setState(() {
      _views = views;
      if (!views.any((view) => view.viewId == _activeViewId)) {
        _activeViewId =
            WidgetsBinding.instance.platformDispatcher.implicitView!.viewId;
      }
    });
  }

  void _activateView(int viewId) {
    if (_activeViewId != viewId) {
      setState(() => _activeViewId = viewId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _displayChannel.setMethodCallHandler(null);
    _credentialController.dispose();
    _feature.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryViewId = View.of(context).viewId;
    return ViewAnchor(
      view: ViewCollection(
        views: [
          for (final view in _views)
            if (view.viewId != primaryViewId)
              View(
                key: ValueKey(view.viewId),
                view: view,
                child: _createDisplay(view.viewId),
              ),
        ],
      ),
      child: _createDisplay(primaryViewId),
    );
  }

  Widget _createDisplay(int viewId) {
    return MaterialApp(
      title: 'Akari Greeter',
      debugShowCheckedModeBanner: false,
      theme: _theme.materialTheme,
      home: Scaffold(
        body: Listener(
          onPointerDown: (_) => _activateView(viewId),
          child: GreeterSceneAdapter(
            feature: _feature,
            theme: _theme,
            credentialController: _credentialController,
            isActive: viewId == _activeViewId,
          ),
        ),
      ),
    );
  }
}
