import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'code_inspector.dart';
import 'node_inspector.dart';
import 'scene_editor.dart';
import 'studio_canvas.dart';
import 'studio_sidebar.dart';
import 'studio_status_bar.dart';
import 'studio_toolbar.dart';
import 'studio_workspace.dart';
import 'studio_assets.dart';
import 'studio_preferences.dart';
import 'studio_settings.dart';
import 'studio_theme_project.dart';
import 'studio_theme_selector.dart';

class ThemeStudioApp extends StatefulWidget {
  const ThemeStudioApp({
    required this.projects,
    required this.initialThemePackageName,
    super.key,
  });

  final List<StudioThemeProject> projects;
  final String initialThemePackageName;

  @override
  State<ThemeStudioApp> createState() => _ThemeStudioAppState();
}

class _ThemeStudioAppState extends State<ThemeStudioApp> {
  SceneEditor? _editor;
  late ThemeDefinition _theme;
  late String _path;
  late List<String> _scenePaths;
  late StudioThemeProject _project;
  bool _loadingFile = false;
  late StudioAssets _compiledAssets;
  late StudioAssets _assets;
  List<String> _assetPaths = [];
  String? _error;
  StudioPreferences _preferences = const StudioPreferences();
  bool _preferencesReady = false;
  bool _dormant = false;
  bool _inspect = false;
  bool _confirmReload = false;
  int _seedRevision = 0;
  String? _lastBackgroundAsset;

  @override
  void initState() {
    super.initState();
    _project = widget.projects.firstWhere(
      (project) => project.packageName == widget.initialThemePackageName,
    );
    _compiledAssets = StudioAssets(
      directory: Directory(_project.directory),
      packageName: _project.packageName,
    );
    _assets = _compiledAssets;
    _updateTheme(_project.themeBuilder());
    _scenePaths = [..._project.scenePaths];
    _path = _scenePaths.first;
    _openScene(_path);
    unawaited(_loadSeed());
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    try {
      final preferences = await StudioPreferences.load();
      if (mounted) setState(() => _preferences = preferences);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _preferencesReady = true);
    }
  }

  Future<void> _savePreferences(StudioPreferences preferences) async {
    try {
      await preferences.save();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Preferences were not saved: $error');
      }
    }
  }

  void _openSettings(BuildContext context) {
    final editor = _editor;
    if (editor == null || !editor.applyDraft()) return;
    showOverlay<void>(
      context,
      const DialogConfiguration(),
      builder: (context) => StudioSettings(
        document: editor.document,
        preferences: _preferences,
        assetPaths: _assetPaths,
        resolveAssetImage: _assets.getImageProvider,
        onApply: (canvas, background, preferences) {
          editor.updateScene(canvas: canvas, background: background);
          setState(() {
            _preferences = preferences;
            _error = null;
          });
          unawaited(_savePreferences(preferences));
        },
      ),
    );
  }

  void _updateTheme(ThemeDefinition theme) {
    _editor?.updateAuthoring(
      componentCatalog: theme.componentCatalog,
      layout: theme.layout,
    );
    _theme = theme.copyWith(
      bundle: theme.bundle.copyWith(
        backgrounds: {
          ...theme.bundle.backgrounds,
          SceneBackgroundKind.image: ImageBackgroundRenderer(
            resolveImage: (asset) => _assets.getImageProvider(asset),
          ),
        },
      ),
    );
  }

  static String? _getEffectiveBackgroundAsset(SceneBackground background) {
    return background.kind == SceneBackgroundKind.image
        ? background.asset
        : null;
  }

  void _onEditorChanged() {
    final editor = _editor;
    if (editor == null) return;
    final currentAsset = _getEffectiveBackgroundAsset(
      editor.document.background,
    );
    if (currentAsset != _lastBackgroundAsset) {
      _lastBackgroundAsset = currentAsset;
      unawaited(_loadSeed());
    }
  }

  void _setEditor(SceneEditor editor) {
    _editor?.removeListener(_onEditorChanged);
    _editor?.dispose();
    _editor = editor..addListener(_onEditorChanged);
    _lastBackgroundAsset = _getEffectiveBackgroundAsset(
      editor.document.background,
    );
  }

  Future<void> _loadSeed() async {
    final revision = ++_seedRevision;
    final editor = _editor;
    final asset = editor != null
        ? _getEffectiveBackgroundAsset(editor.document.background)
        : _getEffectiveBackgroundAsset(_theme.document.background);
    Color? seed;
    if (asset != null) {
      final file = _assets.findFile(asset);
      if (file != null && file.existsSync()) {
        try {
          final bytes = await file.readAsBytes();
          seed = await extractSeedFromBytes(bytes);
        } on Object {
          seed = null;
        }
      } else {
        seed = await _theme.findBackgroundSeed();
      }
    }
    if (!mounted || revision != _seedRevision) return;
    setState(() => _refreshTheme(seed: seed));
  }

  void _refreshTheme({Color? seed}) {
    try {
      _updateTheme(_project.themeBuilder(seed: seed));
    } on FormatException catch (error) {
      _error = 'Cannot refresh theme: ${error.message}';
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _lastBackgroundAsset = null;
    _refreshTheme();
    unawaited(_loadSeed());
  }

  @override
  void dispose() {
    _editor?.removeListener(_onEditorChanged);
    _editor?.dispose();
    super.dispose();
  }

  void _openScene(String path) {
    try {
      final assets = StudioAssets.findForScene(File(path)) ?? _compiledAssets;
      final assetPaths = assets.getAssets();
      final editor = SceneEditor(
        File(path),
        componentCatalog: _theme.componentCatalog,
        layout: _theme.layout,
      );
      _setEditor(editor);
      _assets = assets;
      _assetPaths = assetPaths;
      _path = path;
      if (!_scenePaths.contains(path)) _scenePaths.add(path);
      _error = null;
      _confirmReload = false;
      unawaited(_loadSeed());
    } on Object catch (error) {
      _error = '$error';
    }
  }

  Future<void> _switchTheme(
    StudioThemeProject project,
    BuildContext context, {
    String? scenePath,
  }) async {
    if (!await _confirmSwitch(context)) return;
    if (!mounted) return;
    try {
      // Prepare the entire target before releasing the current session. A bad
      // preset file must leave the working document and its renderer intact.
      final theme = project.themeBuilder();
      final assets = StudioAssets(
        directory: Directory(project.directory),
        packageName: project.packageName,
      );
      final assetPaths = assets.getAssets();
      final editor = SceneEditor(
        File(scenePath ?? project.scenePaths.first),
        componentCatalog: theme.componentCatalog,
        layout: theme.layout,
      );
      setState(() {
        _setEditor(editor);
        _project = project;
        _compiledAssets = assets;
        _assets = assets;
        _assetPaths = assetPaths;
        _scenePaths = [...project.scenePaths];
        _path = editor.file.path;
        if (!_scenePaths.contains(_path)) _scenePaths.add(_path);
        _updateTheme(theme);
        _error = null;
        _confirmReload = false;
      });
      unawaited(_loadSeed());
    } on Object catch (error) {
      setState(() => _error = 'Cannot open theme: $error');
    }
  }

  Future<bool> _confirmSwitch(BuildContext context) async {
    final editor = _editor;
    if (editor == null) return true;
    if (!editor.applyDraft()) return false;
    if (!editor.isDirty) return true;
    final save = await showOverlay<bool>(
      context,
      const DialogConfiguration(),
      builder: (context) => AlertDialog(
        title: const Text('Unsaved scene changes'),
        content: const Text(
          'Save this scene before opening another project or scene?',
        ),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          OutlineButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Discard and switch'),
          ),
          PrimaryButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save and switch'),
          ),
        ],
      ),
    ).future;
    if (!mounted || save == null) return false;
    if (!save) return true;
    _save();
    return !editor.isDirty;
  }

  Future<void> _switchScene(String path, BuildContext context) async {
    if (path == _path) return;
    final StudioAssets? assets;
    try {
      assets = StudioAssets.findForScene(File(path));
    } on Object catch (error) {
      setState(() => _error = '$error');
      return;
    }
    for (final project in widget.projects) {
      if (!identical(project, _project) &&
          project.directory == assets?.directory.path) {
        await _switchTheme(project, context, scenePath: path);
        return;
      }
    }
    if (!context.mounted || !await _confirmSwitch(context)) return;
    if (mounted) setState(() => _openScene(path));
  }

  Future<void> _loadJson(BuildContext context) async {
    setState(() => _loadingFile = true);
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Load scene JSON',
        initialDirectory: File(_path).parent.path,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (!context.mounted || file == null) return;
      await _switchScene(File.fromUri(file.uri).path, context);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loadingFile = false);
    }
  }

  Future<void> _importAsset() async {
    setState(() => _loadingFile = true);
    try {
      final picked = await FilePicker.pickFile(dialogTitle: 'Import asset');
      if (!mounted || picked == null) return;
      final path = _assets.importFile(File.fromUri(picked.uri));
      setState(() {
        _assetPaths = _assets.getAssets();
        _error = null;
      });
      await Clipboard.setData(ClipboardData(text: path));
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loadingFile = false);
    }
  }

  Future<void> _applyBackground(String asset) async {
    final editor = _editor;
    if (editor == null || !editor.applyDraft()) return;
    try {
      final file = _assets.findFile(asset);
      if (file == null) {
        throw FormatException('Asset "$asset" is not a local theme file.');
      }
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      codec.dispose();
      if (!mounted || !identical(editor, _editor)) return;
      editor.updateScene(
        background: editor.document.background.copyWith(
          kind: SceneBackgroundKind.image,
          asset: asset,
        ),
      );
      setState(() => _error = null);
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Cannot use image: $error');
    }
  }

  void _save() {
    final editor = _editor;
    if (editor == null) return;
    try {
      if (!editor.save()) return;
      setState(() {
        _error = null;
        _confirmReload = false;
      });
    } on FileSystemException catch (error) {
      setState(() => _error = error.message);
    }
  }

  void _reload() {
    if (!_confirmReload && _editor != null) {
      setState(() => _confirmReload = true);
      return;
    }
    setState(() {
      final editor = _editor;
      if (editor == null) {
        _openScene(_path);
        return;
      }
      try {
        editor.reload();
        _error = null;
        _confirmReload = false;
      } on Object catch (error) {
        _error = '$error';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShadcnApp(
      title: 'Akari Theme Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: _preferences.palette.getColorScheme(Brightness.light),
        radius: 0.5,
      ),
      darkTheme: ThemeData(
        colorScheme: _preferences.palette.getColorScheme(Brightness.dark),
        radius: 0.5,
      ),
      themeMode: _preferences.themeMode,
      home: Builder(builder: _buildWorkspace),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    final editor = _editor;
    return StudioWorkspace(
      onSave: _save,
      toolbar: StudioToolbar(
        themeId: _theme.id,
        readOnly: _inspect,
        editor: editor,
        preferencesReady: _preferencesReady,
        onOpenSettings: () => _openSettings(context),
        onSave: _save,
      ),
      sidebar: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioThemeSelector(
            projects: widget.projects,
            selected: _project,
            onChanged: (project) => unawaited(_switchTheme(project, context)),
          ),
          const Divider(),
          Expanded(
            child: StudioSidebar(
              scenePaths: _scenePaths,
              assetPaths: _assetPaths,
              resolveAssetImage: _assets.getImageProvider,
              editor: editor,
              loadingFile: _loadingFile,
              readOnly: _inspect,
              onLoadJson: () => _loadJson(context),
              onSwitchScene: (path) => _switchScene(path, context),
              onImportAsset: _importAsset,
              onApplyBackground: _applyBackground,
            ),
          ),
        ],
      ),
      canvas: StudioCanvas(
        editor: editor,
        theme: _theme,
        preferences: _preferences,
        dormant: _dormant,
        readOnly: _inspect,
        onToggleDormant: () => setState(() => _dormant = !_dormant),
      ),
      inspector: editor == null
          ? const SizedBox()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      for (final inspect in [false, true])
                        Expanded(
                          child: Button(
                            style: _inspect == inspect
                                ? const ButtonStyle.secondary()
                                : const ButtonStyle.ghost(),
                            onPressed: () {
                              if (!editor.applyDraft()) return;
                              setState(() => _inspect = inspect);
                            },
                            child: Text(inspect ? 'Inspect code' : 'Design'),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _inspect
                      ? CodeInspector(key: ObjectKey(editor), editor: editor)
                      : NodeInspector(
                          controller: editor.inspector,
                          componentCatalog: editor.componentCatalog,
                          onApply: editor.applyDraft,
                        ),
                ),
              ],
            ),
      statusBar: StudioStatusBar(
        path: _path,
        error: _error,
        confirmReload: _confirmReload,
        onCancelReload: () => setState(() => _confirmReload = false),
        onReload: _reload,
      ),
    );
  }
}
