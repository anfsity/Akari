import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_project/theme_project.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../authoring/studio_create_theme.dart';
import '../authoring/studio_theme_project.dart';
import '../canvas/studio_canvas.dart';
import '../model/studio_preferences.dart';
import '../resources/studio_asset_actions.dart';
import '../resources/studio_assets.dart';
import 'studio_app_dialogs.dart';
import 'studio_app_panes.dart';
import 'studio_settings.dart';
import 'studio_status_bar.dart';
import 'studio_toolbar.dart';
import 'studio_workspace.dart';

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
  final _canvasKey = GlobalKey<StudioCanvasState>();
  late ThemeDefinition _theme;
  late String _path;
  late List<String> _scenePaths;
  late StudioThemeProject _project;
  late final List<StudioThemeProject> _projects;
  bool _loadingFile = false;
  late StudioAssets _compiledAssets;
  late StudioAssets _assets;
  List<String> _assetPaths = [];
  String? _error;
  StudioPreferences _preferences = const StudioPreferences();
  bool _preferencesReady = false;
  bool _dormant = false;
  bool _inspect = false;
  bool _effects = false;
  bool _confirmReload = false;
  int _seedRevision = 0;
  int _assetActionRevision = 0;
  final Map<String, List<String>> _createdScenesByProject = {};
  String? _lastBackgroundAsset;
  Map<String, String> _lastThemeProperties = const {};
  Color? _themeSeed;

  static String _getCanonicalDirectoryPath(String path) {
    final directory = Directory(path);
    return directory.existsSync() ? directory.resolveSymbolicLinksSync() : path;
  }

  List<String> _loadProjectScenePaths(StudioThemeProject project) {
    final result = <String>[];
    final seenCanonical = <String>{};
    void addPath(String path) {
      final file = File(path);
      final canonical = file.existsSync()
          ? file.resolveSymbolicLinksSync()
          : path;
      if (seenCanonical.add(canonical)) result.add(path);
    }

    for (final path in project.scenePaths) {
      addPath(path);
    }
    if (File('${project.directory}/pubspec.yaml').existsSync()) {
      for (final file in findThemeSceneFiles(Directory(project.directory))) {
        addPath(file.path);
      }
    }
    final created =
        _createdScenesByProject[_getCanonicalDirectoryPath(project.directory)];
    if (created != null) {
      for (final path in created) {
        addPath(path);
      }
    }
    return result;
  }

  void _includeScenePath(
    String path,
    StudioAssets assets,
    StudioThemeProject project,
  ) {
    if (assets.directory.path ==
            _getCanonicalDirectoryPath(project.directory) &&
        !_scenePaths.contains(path)) {
      _scenePaths.add(path);
    }
  }

  @override
  void initState() {
    super.initState();
    sceneFontFamilies.addListener(_onSceneFontsChanged);
    _projects = [...widget.projects];
    _project = _projects.firstWhere(
      (project) => project.packageName == widget.initialThemePackageName,
    );
    _compiledAssets = StudioAssets(
      directory: Directory(_project.directory),
      packageName: _project.packageName,
    );
    _assets = _compiledAssets;
    _updateTheme(_project.themeBuilder());
    _scenePaths = _loadProjectScenePaths(_project);
    _path =
        _scenePaths.firstOrNull ??
        '${_project.directory}/lib/default.scene.json';
    if (_scenePaths.isNotEmpty) {
      _openScene(_path);
    } else {
      _error = 'No scene files found in ${_project.packageName}.';
    }
    unawaited(_loadPreferences());
  }

  void _onSceneFontsChanged() {
    if (!mounted) return;
    _editor?.updateAuthoring(
      componentCatalog: _theme.componentCatalog,
      presetCatalog: _theme.presetCatalog,
      layout: _theme.layout,
      minHitTarget: _theme.bundle.tokens.minHitTarget,
      fontFamilies: sceneFontFamilies.value,
    );
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
    if (_inspect || editor == null || !editor.tryApplyDraft()) return;
    showOverlay<void>(
      context,
      const DialogConfiguration(),
      builder: (context) => StudioSettings(
        document: editor.document,
        preferences: _preferences,
        assetPaths: _assetPaths,
        resolveAssetImage: _assets.getImageProvider,
        supportsImageBackground: _theme.bundle.backgrounds.containsKey(
          SceneBackgroundKind.image,
        ),
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
      presetCatalog: theme.presetCatalog,
      layout: theme.layout,
      minHitTarget: theme.bundle.tokens.minHitTarget,
      fontFamilies: sceneFontFamilies.value,
    );
    _theme = theme.copyWith(
      bundle: theme.bundle.copyWith(
        backgrounds: {
          for (final entry in theme.bundle.backgrounds.entries)
            entry.key: entry.value.getWithImageResolver(
              _assets.getImageProvider,
            ),
        },
      ),
    );
  }

  void _onEditorChanged() {
    final editor = _editor;
    if (editor == null) return;
    if (!mapEquals(_lastThemeProperties, editor.document.themeProperties)) {
      _lastThemeProperties = editor.document.themeProperties;
      setState(() => _refreshTheme(seed: _themeSeed));
    }
    final currentAsset = getEffectiveBackgroundAsset(
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
    _lastThemeProperties = editor.document.themeProperties;
    _themeSeed = null;
    _lastBackgroundAsset = getEffectiveBackgroundAsset(
      editor.document.background,
    );
  }

  Future<void> _loadSeed() async {
    final revision = ++_seedRevision;
    final asset = getEffectiveBackgroundAsset(
      _editor?.document.background ?? _theme.document.background,
    );
    final seed = asset == null
        ? null
        : await resolveBackgroundSeedColor(_assets, asset);
    if (!mounted || revision != _seedRevision) return;
    setState(() {
      _themeSeed = seed;
      _refreshTheme(seed: seed);
    });
  }

  void _refreshTheme({Color? seed}) {
    try {
      _updateTheme(
        _project.themeBuilder(seed: seed, document: _editor?.document),
      );
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
    sceneFontFamilies.removeListener(_onSceneFontsChanged);
    _editor?.removeListener(_onEditorChanged);
    _editor?.dispose();
    super.dispose();
  }

  void _openScene(String path) {
    try {
      final assets = StudioAssets.findForScene(File(path)) ?? _compiledAssets;
      final assetPaths = assets.loadAssets();
      final session = _project.createSceneSession(path);
      _setEditor(session.editor);
      _assets = assets;
      _assetPaths = assetPaths;
      _path = path;
      _updateTheme(session.theme);
      _scenePaths = _loadProjectScenePaths(_project);
      _includeScenePath(path, assets, _project);
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
      _openProject(project, scenePath: scenePath);
    } on Object catch (error) {
      setState(() => _error = 'Cannot open theme: $error');
    }
  }

  void _openProject(StudioThemeProject project, {String? scenePath}) {
    // Prepare the entire target before releasing the current session.
    final assets = StudioAssets(
      directory: Directory(project.directory),
      packageName: project.packageName,
    );
    final assetPaths = assets.loadAssets();
    final candidatePaths = _loadProjectScenePaths(project);
    final targetPath = scenePath ?? candidatePaths.firstOrNull;
    if (targetPath == null) {
      throw FormatException('No scene files found in ${project.packageName}.');
    }
    final session = project.createSceneSession(targetPath);
    setState(() {
      if (!_projects.contains(project)) _projects.add(project);
      _setEditor(session.editor);
      _project = project;
      _compiledAssets = assets;
      _assets = assets;
      _assetPaths = assetPaths;
      _scenePaths = _loadProjectScenePaths(project);
      _path = session.editor.file.path;
      _includeScenePath(_path, assets, project);
      _updateTheme(session.theme);
      _error = null;
      _confirmReload = false;
    });
    unawaited(_loadSeed());
  }

  void _openCreateTheme(BuildContext context) {
    final editor = _editor;
    if (editor == null || !editor.tryApplyDraft()) return;
    final source = _project;
    final document = editor.document;
    final assets = _assets;
    showOverlay<void>(
      context,
      const DialogConfiguration(barrierDismissible: false),
      builder: (context) => StudioCreateTheme(
        sourceLabel: _theme.id,
        initialLocation: Directory(source.directory).parent.path,
        existingNames: _projects.map((project) => project.packageName).toSet(),
        onCreate: (packageName, destination) async {
          final project = await source.createTheme(
            packageName: packageName,
            destination: destination,
            document: document,
            assets: assets,
            additionalAssets: [
              for (final sibling in _projects)
                if (sibling.packageName != assets.packageName)
                  StudioAssets(
                    directory: Directory(sibling.directory),
                    packageName: sibling.packageName,
                  ),
            ],
          );
          if (!mounted) return;
          _openProject(project);
        },
      ),
    );
  }

  Future<bool> _confirmSwitch(BuildContext context) async {
    final editor = _editor;
    if (editor == null) return true;
    if (!editor.tryApplyDraft()) return false;
    if (!editor.isDirty) return true;
    final save = await confirmUnsavedSceneSwitch(context);
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
    for (final project in _projects) {
      if (!identical(project, _project) &&
          _getCanonicalDirectoryPath(project.directory) ==
              assets?.directory.path) {
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
        _assetPaths = _assets.loadAssets();
        _error = null;
      });
      await Clipboard.setData(ClipboardData(text: path));
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loadingFile = false);
    }
  }

  Future<void> _runAssetAction(
    Future<void> Function(SceneEditor editor, bool Function() isCurrent)
    action, {
    required String errorPrefix,
    bool requiresSelection = false,
  }) async {
    final editor = _editor;
    if (editor == null ||
        (requiresSelection && editor.selectedIds.isEmpty) ||
        !editor.tryApplyDraft()) {
      return;
    }
    final revision = ++_assetActionRevision;
    bool isCurrent() =>
        mounted &&
        revision == _assetActionRevision &&
        identical(editor, _editor);
    try {
      await action(editor, isCurrent);
      if (!isCurrent()) return;
      setState(() => _error = null);
    } on Object catch (error) {
      if (mounted && revision == _assetActionRevision) {
        setState(() => _error = '$errorPrefix: $error');
      }
    }
  }

  Future<void> _applyBackground(String asset) =>
      _runAssetAction((editor, isCurrent) async {
        await validateImageAssetFile(_assets, asset);
        if (!isCurrent()) return;
        editor.updateScene(
          background: editor.document.background.copyWith(
            kind: SceneBackgroundKind.image,
            asset: asset,
          ),
        );
      }, errorPrefix: 'Cannot use image');

  Future<void> _applyFont(String asset) => _runAssetAction(
    (editor, isCurrent) async {
      await _assets.loadFontPreview(asset);
      if (!isCurrent() || editor.selectedIds.isEmpty) return;
      final style =
          editor.document.styleTokens[editor.selectedNode.styleToken] ??
          const SceneStyle();
      editor.updateSelectionStyle(style.copyWith(fontAsset: asset));
    },
    errorPrefix: 'Cannot apply font',
    requiresSelection: true,
  );

  Future<void> _placeAsset(SceneAsset asset) =>
      _runAssetAction((editor, isCurrent) async {
        await validatePlaceableAsset(_assets, asset);
        if (!isCurrent()) return;
        editor.createAssetNode(asset);
      }, errorPrefix: 'Cannot place asset');

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

  Future<void> _createScene(BuildContext context) async {
    if (!await _confirmSwitch(context) || !context.mounted) return;
    final path = await showOverlay<String>(
      context,
      const DialogConfiguration(),
      builder: (context) => StudioNewSceneDialog(
        directoryPath: _assets.directory.path,
        canvas: _editor?.document.canvas ?? const SceneCanvas(),
      ),
    ).future;
    if (mounted && path != null) {
      final projectKey = _getCanonicalDirectoryPath(_project.directory);
      if (_assets.directory.path == projectKey) {
        final created = _createdScenesByProject.putIfAbsent(
          projectKey,
          () => [],
        );
        if (!created.contains(path)) created.add(path);
      }
      setState(() => _openScene(path));
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
        _assetPaths = _assets.loadAssets();
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
      builder: (context, child) => StudioAppThemeOverrides(child: child!),
      home: Builder(builder: _buildWorkspace),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    final editor = _editor;
    return StudioWorkspace(
      onSave: _save,
      onOpenSettings: _inspect ? null : () => _openSettings(context),
      input: _preferences.input,
      onCanvasKeyEvent: (event) =>
          _canvasKey.currentState?.handleKeyEvent(event) ??
          KeyEventResult.ignored,
      toolbar: StudioToolbar(
        themeId: _theme.id,
        scenePath: _path,
        scenePaths: _scenePaths,
        onSwitchScene: (path) => _switchScene(path, context),
        loadingFile: _loadingFile,
        readOnly: _inspect,
        editor: editor,
        preferencesReady: _preferencesReady,
        onOpenSettings: () => _openSettings(context),
        onSave: _save,
        onCreateTheme: () => _openCreateTheme(context),
        onCreateScene: () => _createScene(context),
        onReload: _reload,
        onLoadJson: () => _loadJson(context),
      ),
      sidebar: StudioProjectSidebar(
        projects: _projects,
        selectedProject: _project,
        onSwitchTheme: (project) => unawaited(_switchTheme(project, context)),
        assetPaths: _assetPaths,
        assets: _assets,
        editor: editor,
        loadingFile: _loadingFile,
        readOnly: _inspect,
        supportsImageBackground: _theme.bundle.backgrounds.containsKey(
          SceneBackgroundKind.image,
        ),
        onPlaceAsset: _placeAsset,
        onApplyFont: _applyFont,
        onImportAsset: _importAsset,
        onApplyBackground: _applyBackground,
      ),
      canvas: StudioCanvas(
        key: _canvasKey,
        editor: editor,
        theme: _theme,
        preferences: _preferences,
        dormant: _dormant,
        readOnly: _inspect,
        onToggleDormant: () => setState(() => _dormant = !_dormant),
        assetImageResolver: _assets.getImageProvider,
        assetSvgLoader: _assets.loadTextAsset,
        assetFontLoader: _assets.loadFontPreview,
        shaderLoader: _assets.loadShaderProgram,
      ),
      inspector: editor == null
          ? const SizedBox()
          : StudioInspectorPane(
              editor: editor,
              theme: _theme,
              assets: _assets,
              inspect: _inspect,
              effects: _effects,
              onSelectTab: (index) {
                if (!editor.tryApplyDraft()) return;
                setState(() {
                  _inspect = index == 2;
                  _effects = index == 1;
                });
              },
              onAssetsChanged: () =>
                  setState(() => _assetPaths = _assets.loadAssets()),
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
