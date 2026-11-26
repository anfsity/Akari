import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show mapEquals;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_project/theme_project.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../authoring/studio_create_theme.dart';
import '../authoring/studio_theme_project.dart';
import '../canvas/studio_canvas.dart';
import '../inspector/code_inspector.dart';
import '../inspector/node_inspector.dart';
import '../inspector/studio_effects_inspector.dart';
import '../model/studio_preferences.dart';
import '../resources/confined_path.dart';
import '../resources/studio_assets.dart';
import '../ui/studio_form.dart';
import 'studio_settings.dart';
import 'studio_sidebar.dart';
import 'studio_status_bar.dart';
import 'studio_theme_selector.dart';
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
  ui.Color? _themeSeed;

  static String _getCanonicalDirectoryPath(String path) {
    final directory = Directory(path);
    return directory.existsSync() ? directory.resolveSymbolicLinksSync() : path;
  }

  List<String> _getProjectScenePaths(StudioThemeProject project) {
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
    _scenePaths = _getProjectScenePaths(_project);
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

  static String? _getEffectiveBackgroundAsset(SceneBackground background) {
    return background.kind == SceneBackgroundKind.image
        ? background.asset
        : null;
  }

  void _onEditorChanged() {
    final editor = _editor;
    if (editor == null) return;
    if (!mapEquals(_lastThemeProperties, editor.document.themeProperties)) {
      _lastThemeProperties = editor.document.themeProperties;
      setState(() => _refreshTheme(seed: _themeSeed));
    }
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
    _lastThemeProperties = editor.document.themeProperties;
    _themeSeed = null;
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
          seed = await decodeSeedColor(bytes);
        } on Object {
          seed = null;
        }
      } else {
        try {
          seed = await loadSeedColor(asset);
        } on Object {
          seed = null;
        }
      }
    }
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
      final assetPaths = assets.getAssets();
      final session = _project.createSceneSession(path);
      _setEditor(session.editor);
      _assets = assets;
      _assetPaths = assetPaths;
      _path = path;
      _updateTheme(session.theme);
      _scenePaths = _getProjectScenePaths(_project);
      if (assets.directory.path ==
              _getCanonicalDirectoryPath(_project.directory) &&
          !_scenePaths.contains(path)) {
        _scenePaths.add(path);
      }
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
    final assetPaths = assets.getAssets();
    final candidatePaths = _getProjectScenePaths(project);
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
      _scenePaths = _getProjectScenePaths(project);
      _path = session.editor.file.path;
      if (assets.directory.path ==
              _getCanonicalDirectoryPath(project.directory) &&
          !_scenePaths.contains(_path)) {
        _scenePaths.add(_path);
      }
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
        final file = _assets.findFile(asset);
        if (file == null) {
          throw FormatException('Asset "$asset" is not a local theme file.');
        }
        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        codec.dispose();
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
        if (asset.kind == SceneAssetKind.svg) {
          final source = await _assets.loadTextAsset(asset.path);
          final picture = await vg.loadPicture(SvgStringLoader(source), null);
          picture.picture.dispose();
        } else {
          final bytes = await _assets.loadBytes(asset.path);
          final codec = await ui.instantiateImageCodec(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
          codec.dispose();
        }
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
      builder: (context) => _NewSceneDialog(
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
        _assetPaths = _assets.getAssets();
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
      builder: (context, child) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        return ComponentTheme<OutlineButtonTheme>(
          data: OutlineButtonTheme(
            decoration: (context, states, decoration) =>
                (decoration as BoxDecoration).copyWith(
                  color:
                      states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.pressed)
                      ? colors.accent
                      : colors.background,
                ),
          ),
          child: ComponentTheme<SliderTheme>(
            data: SliderTheme(
              trackHeight: 4,
              trackColor: colors.muted,
              thumbColor: colors.background,
              thumbBorderColor: colors.primary.withValues(alpha: .5),
              thumbFocusedBorderColor: colors.primary,
              thumbSize: 16,
            ),
            child: ComponentTheme<ScrollbarTheme>(
              data: ScrollbarTheme(
                thickness: 4 * theme.scaling,
                color: colors.mutedForeground.withValues(alpha: .35),
                radius: const Radius.circular(8),
              ),
              child: child!,
            ),
          ),
        );
      },
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
      sidebar: _StudioProjectSidebar(
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
          : _StudioInspectorPane(
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
                  setState(() => _assetPaths = _assets.getAssets()),
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

class _StudioProjectSidebar extends StatelessWidget {
  const _StudioProjectSidebar({
    required this.projects,
    required this.selectedProject,
    required this.onSwitchTheme,
    required this.assetPaths,
    required this.assets,
    required this.editor,
    required this.loadingFile,
    required this.readOnly,
    required this.supportsImageBackground,
    required this.onPlaceAsset,
    required this.onApplyFont,
    required this.onImportAsset,
    required this.onApplyBackground,
  });

  final List<StudioThemeProject> projects;
  final StudioThemeProject selectedProject;
  final ValueChanged<StudioThemeProject> onSwitchTheme;
  final List<String> assetPaths;
  final StudioAssets assets;
  final SceneEditor? editor;
  final bool loadingFile;
  final bool readOnly;
  final bool supportsImageBackground;
  final ValueChanged<SceneAsset> onPlaceAsset;
  final ValueChanged<String> onApplyFont;
  final VoidCallback onImportAsset;
  final ValueChanged<String> onApplyBackground;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StudioThemeSelector(
        projects: projects,
        selected: selectedProject,
        onChanged: onSwitchTheme,
      ),
      const Divider(),
      Expanded(
        child: StudioSidebar(
          assetPaths: assetPaths,
          resolveAssetImage: assets.getImageProvider,
          loadAssetText: assets.loadTextAsset,
          loadFontPreview: assets.loadFontPreview,
          onPlaceAsset: onPlaceAsset,
          onApplyFont: onApplyFont,
          editor: editor,
          loadingFile: loadingFile,
          readOnly: readOnly,
          onImportAsset: onImportAsset,
          onApplyBackground: supportsImageBackground ? onApplyBackground : null,
        ),
      ),
    ],
  );
}

class _StudioInspectorPane extends StatelessWidget {
  const _StudioInspectorPane({
    required this.editor,
    required this.theme,
    required this.assets,
    required this.inspect,
    required this.effects,
    required this.onSelectTab,
    required this.onAssetsChanged,
  });

  final SceneEditor editor;
  final ThemeDefinition theme;
  final StudioAssets assets;
  final bool inspect;
  final bool effects;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onAssetsChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Tabs(
          index: inspect
              ? 2
              : effects
              ? 1
              : 0,
          expand: true,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          onChanged: onSelectTab,
          children: [
            for (final label in ['Design', 'Effects', 'Inspect code'])
              TabItem(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ).small(),
                ),
              ),
          ],
        ),
      ),
      const Divider(),
      Expanded(
        child: inspect
            ? CodeInspector(key: ObjectKey(editor), editor: editor)
            : effects
            ? StudioEffectsInspector(
                editor: editor,
                theme: theme,
                assets: assets,
                onAssetsChanged: onAssetsChanged,
              )
            : NodeInspector(
                editor: editor,
                controller: editor.inspector,
                componentCatalog: editor.componentCatalog,
                onApply: editor.tryApplyDraft,
              ),
      ),
    ],
  );
}

class _NewSceneDialog extends StatefulWidget {
  const _NewSceneDialog({required this.directoryPath, required this.canvas});

  final String directoryPath;
  final SceneCanvas canvas;

  @override
  State<_NewSceneDialog> createState() => _NewSceneDialogState();
}

class _NewSceneDialogState extends State<_NewSceneDialog> {
  final _name = TextEditingController(text: 'new-scene');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final id = _name.text.trim();
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(id)) {
      setState(() => _error = 'Use a lower-case scene name.');
      return;
    }
    final file = findConfinedFile(
      Directory(widget.directoryPath),
      'lib/$id.scene.json',
    );
    if (file == null) {
      setState(
        () => _error = 'Scene files must stay inside the current theme.',
      );
      return;
    }
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      setState(() => _error = 'This scene already exists.');
      return;
    }
    try {
      final source = encodeSceneDocument(
        SceneDocument(
          id: id,
          version: currentSceneVersion,
          canvas: widget.canvas,
          background: const SceneBackground(kind: SceneBackgroundKind.solid),
          nodes: const [
            SceneNode(
              id: 'artboard',
              componentId: 'frame',
              layout: SceneLayout(),
              rect: SceneRect(x: 0, y: 0, width: 1, height: 1),
            ),
          ],
        ),
      );
      writeFileAtomically(file, '$source\n', tempName: '$id.scene.json');
      Navigator.of(context).pop(file.path);
    } on FileSystemException catch (failure) {
      setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New scene'),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Start with an empty artboard in the current theme.'),
          const Gap(12),
          TextField(key: const ValueKey('new-scene-name'), controller: _name),
          if (_error != null) StudioFormError(_error!),
        ],
      ),
    ),
    actions: [
      OutlineButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      PrimaryButton(
        key: const ValueKey('confirm-new-scene'),
        onPressed: _create,
        child: const Text('Create scene'),
      ),
    ],
  );
}
