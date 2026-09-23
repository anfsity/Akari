import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mozais_greeter_ui/mozais_greeter_ui.dart';

import 'editor_controller.dart';
import 'editor_settings_controller.dart';
import 'editor_settings_scope.dart';
import 'editor_status.dart';
import 'editor_strings.dart';
import 'editor_theme.dart';
import 'file_picker_dialog.dart';
import 'inspector_panel.dart';
import 'node_list_panel.dart';
import 'pane_divider.dart';
import 'repo_root.dart';
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
  late final GreeterFeature _greeterFeature;
  PreviewMode _previewMode = PreviewMode.outline;
  bool _interacting = false;
  double _leftWidth = 240;
  double _rightWidth = 300;
  bool _rightCollapsed = false;

  static const _leftMinWidth = 160.0;
  static const _leftMaxWidth = 420.0;
  static const _rightMinWidth = 240.0;
  static const _rightMaxWidth = 640.0;

  @override
  void initState() {
    super.initState();
    _controller = SceneEditorController();
    _pathController = TextEditingController();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _handleExitRequest,
    );
    _greeterFeature = GreeterFeature(gateway: DemoGreeterGateway());
    unawaited(_greeterFeature.initialize());
    final configured = widget.settings.settings.defaultScenePath;
    final path = resolveStartupScenePath(configured);
    _controller.setPath(path);
    _pathController.text = path;
    if (path.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_openPath(path)),
      );
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _greeterFeature.dispose();
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
      _UnsavedChoice.save => await _controller.save() && !_controller.dirty,
      _UnsavedChoice.discard => true,
      _UnsavedChoice.cancel || null => false,
    };
  }

  Future<void> _open() async {
    if (!await _confirmDiscard()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final current = _controller.path;
    final file = await pickFile(
      context,
      initialDirectory: current.isEmpty ? null : File(current).parent,
      extensions: const {'json'},
    );
    if (file == null) {
      return;
    }
    await _openPath(file.path);
  }

  Future<void> _openPath(String path) async {
    _pathController.text = path;
    final opened = await _controller.open(path);
    if (!mounted) {
      return;
    }
    if (opened) {
      _rememberPath();
    } else if (_controller.document != null) {
      _pathController.text = _controller.path;
    }
  }

  Future<void> _save() async {
    final saved = await _controller.save();
    if (mounted && saved) {
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

  bool get _settingsAreDark =>
      editorThemeFor(widget.settings.settings.themeId).palette.brightness ==
      Brightness.dark;

  void _toggleThemeBrightness() {
    final settings = widget.settings.settings;
    widget.settings.update(
      settings.copyWith(themeId: toggledThemeBrightness(settings.themeId)),
    );
  }

  void _resizeLeft(double delta) {
    setState(() {
      _leftWidth = (_leftWidth + delta).clamp(_leftMinWidth, _leftMaxWidth);
    });
  }

  void _resizeRight(double delta) {
    setState(() {
      _rightWidth = (_rightWidth - delta).clamp(_rightMinWidth, _rightMaxWidth);
    });
  }

  void _toggleRight() {
    setState(() => _rightCollapsed = !_rightCollapsed);
  }

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): _open,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _open,
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelectedNode,
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(strings.appTitle),
            ],
          ),
          actions: [
            ListenableBuilder(
              listenable: _controller.operationListenable,
              builder: (context, _) {
                final enabled = !_controller.opening && !_controller.saving;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 420,
                      child: TextField(
                        controller: _pathController,
                        enabled: enabled,
                        decoration: InputDecoration(
                          hintText: strings.pathHint,
                          isDense: true,
                        ),
                        onChanged: _controller.setPath,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: enabled ? _open : null,
                      child: Text(strings.open),
                    ),
                    TextButton(
                      onPressed: enabled ? _save : null,
                      child: Text(strings.save),
                    ),
                  ],
                );
              },
            ),
            IconButton(
              tooltip: _settingsAreDark
                  ? strings.useLightTheme
                  : strings.useDarkTheme,
              onPressed: _toggleThemeBrightness,
              icon: Icon(
                _settingsAreDark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
            ),
            if (!_rightCollapsed)
              IconButton(
                tooltip: strings.collapseInspector,
                onPressed: _toggleRight,
                icon: const Icon(Icons.chevron_right),
              ),
            IconButton(
              tooltip: strings.settings,
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(
                  right: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: SizedBox(
                width: _leftWidth,
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    _controller.nodesListenable,
                    _controller.selectionListenable,
                    _controller.documentListenable,
                  ]),
                  builder: (context, _) =>
                      NodeListPanel(controller: _controller),
                ),
              ),
            ),
            PaneDivider(dragAxis: Axis.horizontal, onDrag: _resizeLeft),
            Expanded(
              child: Column(
                children: [
                  _PreviewToolbar(
                    mode: _previewMode,
                    onChanged: (mode) => setState(() => _previewMode = mode),
                    interacting: _interacting,
                    onInteractingChanged: (value) =>
                        setState(() => _interacting = value),
                  ),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                      ),
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          _controller.documentListenable,
                          _controller.selectionListenable,
                          _controller.predicatesListenable,
                        ]),
                        builder: (context, _) => ScenePreview(
                          controller: _controller,
                          feature: _greeterFeature,
                          mode: _previewMode,
                          interacting: _interacting,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_rightCollapsed)
              _CollapsedInspector(
                tooltip: strings.expandInspector,
                onExpand: _toggleRight,
              )
            else ...[
              PaneDivider(dragAxis: Axis.horizontal, onDrag: _resizeRight),
              SizedBox(
                width: _rightWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border(
                      left: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: InspectorPanel(controller: _controller),
                ),
              ),
            ],
          ],
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: _controller.statusListenable,
          builder: (context, _) => _StatusBar(controller: _controller),
        ),
      ),
    );
  }

  void _deleteSelectedNode() {
    if (_controller.selectedNode != null) {
      _controller.deleteSelected();
    }
  }
}

enum _UnsavedChoice { save, discard, cancel }

/// The narrow rail shown while the inspector is collapsed.
class _CollapsedInspector extends StatelessWidget {
  const _CollapsedInspector({required this.tooltip, required this.onExpand});

  final String tooltip;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onExpand,
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.chevron_left),
      ),
    );
  }
}

class _PreviewToolbar extends StatelessWidget {
  const _PreviewToolbar({
    required this.mode,
    required this.onChanged,
    required this.interacting,
    required this.onInteractingChanged,
  });

  final PreviewMode mode;
  final ValueChanged<PreviewMode> onChanged;
  final bool interacting;
  final ValueChanged<bool> onInteractingChanged;

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            IconButton(
              tooltip: interacting ? strings.editMode : strings.interactMode,
              isSelected: interacting,
              onPressed: () => onInteractingChanged(!interacting),
              icon: const Icon(Icons.touch_app_outlined),
              selectedIcon: const Icon(Icons.touch_app),
            ),
            SegmentedButton<PreviewMode>(
              segments: [
                ButtonSegment(
                  value: PreviewMode.outline,
                  label: Text(strings.outline),
                ),
                ButtonSegment(
                  value: PreviewMode.real,
                  label: Text(strings.real),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ],
        ),
      ),
    );
  }
}

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
