import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

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

class ThemeStudioApp extends StatefulWidget {
  const ThemeStudioApp({
    required this.themeBuilder,
    required this.scenePaths,
    required this.themeDirectory,
    required this.themePackageName,
    super.key,
  });

  final ThemeBuilder themeBuilder;
  final List<String> scenePaths;
  final String themeDirectory;
  final String themePackageName;

  @override
  State<ThemeStudioApp> createState() => _ThemeStudioAppState();
}

class _ThemeStudioAppState extends State<ThemeStudioApp> {
  SceneEditor? _editor;
  late ThemeDefinition _theme;
  late String _path;
  late final List<String> _scenePaths;
  bool _loadingFile = false;
  late final StudioAssets _assets;
  List<String> _assetPaths = [];
  String? _error;
  StudioPreferences _preferences = const StudioPreferences();
  bool _preferencesReady = false;
  bool _dormant = false;
  bool _confirmReload = false;

  @override
  void initState() {
    super.initState();
    _assets = StudioAssets(
      directory: Directory(widget.themeDirectory),
      packageName: widget.themePackageName,
    );
    _updateTheme(widget.themeBuilder());
    _assetPaths = _assets.getAssets();
    _scenePaths = [...widget.scenePaths];
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
    _theme = theme.copyWith(
      bundle: theme.bundle.copyWith(
        backgrounds: {
          ...theme.bundle.backgrounds,
          SceneBackgroundKind.image: ImageBackgroundRenderer(
            resolveImage: _assets.getImageProvider,
          ),
        },
      ),
    );
  }

  Future<void> _loadSeed() async {
    final theme = _theme;
    final seed = await theme.findBackgroundSeed();
    if (!mounted || !identical(theme, _theme) || seed == null) return;
    setState(() => _updateTheme(widget.themeBuilder(seed: seed)));
  }

  @override
  void reassemble() {
    super.reassemble();
    _updateTheme(widget.themeBuilder());
    unawaited(_loadSeed());
  }

  void _openScene(String path) {
    try {
      final editor = SceneEditor(File(path));
      _editor?.dispose();
      _editor = editor;
      _path = path;
      if (!_scenePaths.contains(path)) _scenePaths.add(path);
      _error = null;
      _confirmReload = false;
    } on Object catch (error) {
      _error = '$error';
    }
  }

  void _switchScene(String path) {
    if (_editor?.applyDraft() == false) return;
    if (_editor?.isDirty == true) {
      setState(
        () => _error = 'Save or reload your changes before switching scenes.',
      );
      return;
    }
    setState(() => _openScene(path));
  }

  Future<void> _loadJson() async {
    setState(() => _loadingFile = true);
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Load scene JSON',
        initialDirectory: File(_path).parent.path,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (!mounted || file == null) return;
      _switchScene(File.fromUri(file.uri).path);
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
      final provider = _assets.getImageProvider(asset) as FileImage;
      final codec = await ui.instantiateImageCodec(
        await provider.file.readAsBytes(),
      );
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
  void dispose() {
    _editor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadcnApp(
      title: 'Mozais Theme Studio',
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
      toolbar: StudioToolbar(
        themeId: _theme.id,
        editor: editor,
        preferencesReady: _preferencesReady,
        onOpenSettings: () => _openSettings(context),
        onSave: _save,
      ),
      sidebar: StudioSidebar(
        scenePaths: _scenePaths,
        assetPaths: _assetPaths,
        editor: editor,
        loadingFile: _loadingFile,
        onLoadJson: _loadJson,
        onSwitchScene: _switchScene,
        onImportAsset: _importAsset,
        onApplyBackground: _applyBackground,
      ),
      canvas: StudioCanvas(
        editor: editor,
        theme: _theme,
        preferences: _preferences,
        dormant: _dormant,
        onToggleDormant: () => setState(() => _dormant = !_dormant),
      ),
      inspector: editor == null
          ? const SizedBox()
          : NodeInspector(
              controller: editor.inspector,
              onApply: editor.applyDraft,
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
