import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'editor_controller.dart';
import 'editor_settings_controller.dart';
import 'editor_settings_scope.dart';
import 'editor_status.dart';
import 'editor_strings.dart';
import 'editor_theme.dart';
import 'inspector_panel.dart';
import 'node_list_panel.dart';
import 'scene_preview.dart';
import 'settings_page.dart';

class SceneEditorApp extends StatefulWidget {
  const SceneEditorApp({super.key});

  @override
  State<SceneEditorApp> createState() => _SceneEditorAppState();
}

class _SceneEditorAppState extends State<SceneEditorApp> {
  late final EditorSettingsController _settings;

  @override
  void initState() {
    super.initState();
    _settings = EditorSettingsController.load();
  }

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final strings = _settings.strings;
        return EditorSettingsScope(
          controller: _settings,
          child: EditorStringsScope(
            strings: strings,
            child: MaterialApp(
              title: strings.appTitle,
              debugShowCheckedModeBanner: false,
              theme: editorThemeFor(_settings.settings.themeId).toThemeData(),
              home: EditorScreen(settings: _settings),
            ),
          ),
        );
      },
    );
  }
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({required this.settings, super.key});

  final EditorSettingsController settings;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final SceneEditorController _controller;
  late final TextEditingController _pathController;
  late final AppLifecycleListener _lifecycleListener;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = SceneEditorController();
    _pathController = TextEditingController();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _handleExitRequest,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    final configured = widget.settings.settings.defaultScenePath;
    final path = configured.isNotEmpty ? configured : defaultScenePath() ?? '';
    _controller.setPath(path);
    _pathController.text = path;
    if (path.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _controller.open());
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _controller.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<AppExitResponse> _handleExitRequest() async {
    if (await _confirmDiscard()) {
      return AppExitResponse.exit;
    }
    return AppExitResponse.cancel;
  }

  /// Returns true when it is safe to drop the current document.
  Future<bool> _confirmDiscard() async {
    if (!_controller.dirty || !widget.settings.settings.confirmUnsavedChanges) {
      return true;
    }
    final strings = EditorStringsScope.of(context);
    final choice = await showDialog<_UnsavedChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.unsavedDialogTitle),
        content: Text(strings.unsavedDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_UnsavedChoice.cancel),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_UnsavedChoice.discard),
            child: Text(strings.discard),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_UnsavedChoice.save),
            child: Text(strings.save),
          ),
        ],
      ),
    );
    return switch (choice) {
      _UnsavedChoice.save => await _controller.save(),
      _UnsavedChoice.discard => true,
      _UnsavedChoice.cancel || null => false,
    };
  }

  Future<void> _open() async {
    if (!await _confirmDiscard()) {
      return;
    }
    if (await _controller.open()) {
      _rememberPath();
    }
  }

  Future<void> _save() async {
    if (await _controller.save()) {
      _rememberPath();
    }
  }

  void _rememberPath() {
    final settings = widget.settings.settings;
    widget.settings.update(
      settings.copyWith(defaultScenePath: _controller.path),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsPage(controller: widget.settings),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appTitle),
        actions: [
          SizedBox(
            width: 420,
            child: TextField(
              controller: _pathController,
              decoration: InputDecoration(
                hintText: strings.pathHint,
                isDense: true,
              ),
              onChanged: _controller.setPath,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: _open, child: Text(strings.open)),
          TextButton(onPressed: _save, child: Text(strings.save)),
          IconButton(
            tooltip: strings.settings,
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Row(
          children: [
            SizedBox(
              width: 240,
              child: NodeListPanel(controller: _controller),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: ScenePreview(controller: _controller)),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 360,
              child: InspectorPanel(controller: _controller),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _StatusBar(controller: _controller),
      ),
    );
  }
}

enum _UnsavedChoice { save, discard, cancel }

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final SceneEditorController controller;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (controller.dirty)
            Text(
              strings.unsavedChanges,
              style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              describeEditorStatus(strings, controller.status),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
