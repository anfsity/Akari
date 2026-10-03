import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'node_inspector.dart';
import 'scene_editor.dart';
import 'studio_preview.dart';
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
    _theme = widget.themeBuilder();
    _assets = StudioAssets(
      directory: Directory(widget.themeDirectory),
      packageName: widget.themePackageName,
    );
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

  Future<void> _loadSeed() async {
    final theme = _theme;
    final seed = await theme.findBackgroundSeed();
    if (!mounted || !identical(theme, _theme) || seed == null) return;
    setState(() => _theme = widget.themeBuilder(seed: seed));
  }

  @override
  void reassemble() {
    super.reassemble();
    _theme = widget.themeBuilder();
    unawaited(_loadSeed());
  }

  void _openScene(String path) {
    try {
      final editor = SceneEditor(File(path));
      _editor?.dispose();
      _editor = editor..addListener(_refreshWorkspace);
      editor.inspector.addListener(_refreshWorkspace);
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
      _switchScene(file.path!);
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
      final path = _assets.importFile(File(picked.path!));
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

  void _selectNode(String id) {
    _editor?.selectNode(id);
  }

  void _refreshWorkspace() => setState(() {});

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
        colorScheme: _preferences.darkMode
            ? ColorSchemes.darkZinc
            : ColorSchemes.lightZinc,
        radius: 0.5,
      ),
      home: Builder(builder: _buildWorkspace),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    final editor = _editor;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(1100, constraints.maxWidth),
              height: constraints.maxHeight,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.panelsTopLeft, size: 20),
                        const Gap(12),
                        const Text('Theme Studio').semiBold(),
                        const Gap(16),
                        Text(_theme.id).muted(),
                        const Spacer(),
                        OutlineButton(
                          onPressed: editor != null && _preferencesReady
                              ? () => _openSettings(context)
                              : null,
                          child: const Text('Settings'),
                        ),
                        const Gap(16),
                        Text(
                          editor?.inspector.hasDraft == true ||
                                  editor?.isDirty == true
                              ? 'Unsaved changes'
                              : 'Saved',
                        ).small().muted(),
                        const Gap(16),
                        OutlineButton(
                          onPressed:
                              editor?.inspector.hasDraft == true ||
                                  editor?.canUndo == true
                              ? editor?.undo
                              : null,
                          child: const Text('Undo'),
                        ),
                        const Gap(8),
                        OutlineButton(
                          onPressed: editor?.canRedo == true
                              ? editor?.redo
                              : null,
                          child: const Text('Redo'),
                        ),
                        const Gap(16),
                        PrimaryButton(
                          onPressed: editor == null ? null : _save,
                          child: const Text('Save scene'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 220,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: const Text('SCENES').small().muted(),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: OutlineButton(
                                  onPressed: _loadingFile ? null : _loadJson,
                                  child: const Text('Load JSON'),
                                ),
                              ),
                              const Gap(8),
                              for (final path in _scenePaths)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: GhostButton(
                                    onPressed: () => _switchScene(path),
                                    child: Text(
                                      File(path).uri.pathSegments.last,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              const Gap(16),
                              const Divider(),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: const Text('LAYERS').small().muted(),
                              ),
                              if (editor != null)
                                Expanded(
                                  child: ListView(
                                    children: [
                                      for (final node
                                          in editor
                                              .document
                                              .paintOrder
                                              .reversed)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          child: Button(
                                            key: ValueKey('layer-${node.id}'),
                                            style: node.id == editor.selectedId
                                                ? const ButtonStyle.secondary()
                                                : const ButtonStyle.ghost(),
                                            onPressed: () =>
                                                _selectNode(node.id),
                                            child: SizedBox(
                                              width: double.infinity,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    node.id,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  Text(node.componentId)
                                                      .small()
                                                      .muted(),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              const Divider(),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: OutlineButton(
                                  onPressed: _loadingFile ? null : _importAsset,
                                  child: const Text('Import asset'),
                                ),
                              ),
                              if (_assetPaths.isNotEmpty)
                                SizedBox(
                                  height: 140,
                                  child: ListView(
                                    children: [
                                      for (final asset in _assetPaths)
                                        Row(
                                          children: [
                                            Expanded(
                                              child: GhostButton(
                                                onPressed: () =>
                                                    Clipboard.setData(
                                                      ClipboardData(
                                                        text: asset,
                                                      ),
                                                    ),
                                                child: Text(
                                                  asset.split('/').last,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            if (editor != null)
                                              GhostButton(
                                                onPressed: () =>
                                                    _applyBackground(asset),
                                                child: const Text('Use image'),
                                              ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              if (editor != null)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      OutlineButton(
                                        onPressed: editor.duplicateSelectedNode,
                                        child: const Text('Duplicate node'),
                                      ),
                                      const Gap(8),
                                      OutlineButton(
                                        onPressed: editor.canDeleteNode
                                            ? editor.deleteSelectedNode
                                            : null,
                                        child: const Text('Delete node'),
                                      ),
                                      if (!editor.canDeleteNode) ...[
                                        const Gap(8),
                                        const Text(
                                          'A scene needs at least one node.',
                                        ).small().muted(),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        VerticalDivider(color: colors.border),
                        Expanded(
                          child: ColoredBox(
                            color: colors.muted.withValues(alpha: 0.3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      const Text('Preview').semiBold(),
                                      const Spacer(),
                                      OutlineButton(
                                        onPressed: () => setState(
                                          () => _dormant = !_dormant,
                                        ),
                                        child: Text(
                                          _dormant
                                              ? 'State: Dormant'
                                              : 'State: Login',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    child: editor == null
                                        ? const Center(
                                            child: Text('Unable to open scene'),
                                          )
                                        : StudioPreview(
                                            key: ObjectKey(editor),
                                            theme: _theme.copyWith(
                                              bundle: _theme.bundle.copyWith(
                                                backgrounds: {
                                                  ..._theme.bundle.backgrounds,
                                                  SceneBackgroundKind.image:
                                                      ImageBackgroundRenderer(
                                                        resolveImage: _assets
                                                            .getImageProvider,
                                                      ),
                                                },
                                              ),
                                            ),
                                            document: editor.document,
                                            selectedId: editor.selectedId,
                                            dormant: _dormant,
                                            preferences: _preferences,
                                            onSelect: _selectNode,
                                            onStartDrag: (id) {
                                              if (!editor.selectNode(id)) {
                                                return null;
                                              }
                                              return editor.selectedNode;
                                            },
                                            onMove: editor.updateNode,
                                          ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    editor == null
                                        ? 'Choose a valid scene document.'
                                        : '${editor.document.canvas.referenceWidth} × ${editor.document.canvas.referenceHeight}  ·  Drag nodes to move  ·  Simulated data',
                                    textAlign: TextAlign.center,
                                  ).small().muted(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        VerticalDivider(color: colors.border),
                        SizedBox(
                          width: 300,
                          child: editor == null
                              ? const SizedBox()
                              : NodeInspector(
                                  controller: editor.inspector,
                                  onApply: editor.applyDraft,
                                ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _error ?? _path,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _error == null
                                  ? colors.mutedForeground
                                  : colors.destructive,
                            ),
                          ).small(),
                        ),
                        const Gap(12),
                        if (_confirmReload) ...[
                          const Text('Discard edits and reload?').small(),
                          const Gap(8),
                          GhostButton(
                            onPressed: () =>
                                setState(() => _confirmReload = false),
                            child: const Text('Cancel'),
                          ),
                        ],
                        GhostButton(
                          onPressed: _reload,
                          child: Text(
                            _confirmReload
                                ? 'Discard and reload'
                                : 'Reload from disk',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
