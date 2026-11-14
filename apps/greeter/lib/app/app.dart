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
    this.gateway,
    super.key,
  });

  final ThemeBuilder themeBuilder;

  /// Persistence for the selected session; the default keeps tests isolated.
  final SessionStore sessionStore;

  /// The app owns and closes an injected gateway just as it does its transport.
  final GreeterGateway? gateway;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static const _displayChannel = MethodChannel('akari/displays');
  final _credentialController = TextEditingController();
  late GreeterFeature _feature;
  late ThemeDefinition _theme;
  late List<FlutterView> _views;
  late int _activeViewId;
  Color? _themeSeed;

  int _findDefaultViewId(List<FlutterView> views) =>
      WidgetsBinding.instance.platformDispatcher.implicitView?.viewId ??
      (views.isEmpty ? 0 : views.first.viewId);

  GreeterFeature _createFeature() {
    final backendMode = const String.fromEnvironment(
      'AKARI_BACKEND',
      defaultValue: 'demo',
    );
    return GreeterFeature(
      gateway:
          widget.gateway ??
          (backendMode == 'demo' ? DemoGreeterGateway() : DBusGreeterGateway()),
      sessionStore: widget.sessionStore,
    );
  }

  @override
  void initState() {
    super.initState();
    _views = WidgetsBinding.instance.platformDispatcher.views.toList();
    _activeViewId = _findDefaultViewId(_views);
    WidgetsBinding.instance.addObserver(this);
    // Active display focus is tracked via dual mechanisms: GTK reports window
    // focus changes over the akari/displays MethodChannel, while Listener
    // taps activate views directly during in-engine pointer hit testing.
    _displayChannel.setMethodCallHandler((call) async {
      if (call.method != 'focusView') {
        throw MissingPluginException(
          'Unsupported display channel method: ${call.method}',
        );
      }
      if (call.arguments case final int viewId) {
        _activateView(viewId);
      }
    });
    _feature = _createFeature();
    _theme = widget.themeBuilder();
    unawaited(_loadThemeSeed());
    unawaited(_feature.initialize());
  }

  @override
  void didUpdateWidget(MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.gateway, oldWidget.gateway) ||
        widget.sessionStore != oldWidget.sessionStore) {
      _feature.dispose();
      _credentialController.clear();
      _feature = _createFeature();
      unawaited(_feature.initialize());
    }
    if (!identical(widget.themeBuilder, oldWidget.themeBuilder)) {
      _theme = widget.themeBuilder(seed: _themeSeed);
      unawaited(_loadThemeSeed());
    }
  }

  Future<void> _loadThemeSeed() async {
    final theme = _theme;
    final seed = await theme.findBackgroundSeed();
    // A hot reload can replace the theme while asset decoding is pending.
    // Applying that old seed would overwrite the newly assembled theme.
    // When seed is null (e.g. background image removed), reset _themeSeed.
    if (!mounted || !identical(theme, _theme) || seed == _themeSeed) {
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
        _activeViewId = _findDefaultViewId(views);
      }
    });
  }

  void _activateView(int viewId) {
    if (!mounted ||
        _activeViewId == viewId ||
        !_views.any((view) => view.viewId == viewId)) {
      return;
    }
    setState(() => _activeViewId = viewId);
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
