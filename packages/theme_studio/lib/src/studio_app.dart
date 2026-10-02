import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'node_inspector.dart';
import 'scene_editor.dart';
import 'studio_preview.dart';

class ThemeStudioApp extends StatefulWidget {
  const ThemeStudioApp({
    required this.themeBuilder,
    required this.scenePaths,
    super.key,
  });

  final ThemeBuilder themeBuilder;
  final List<String> scenePaths;

  @override
  State<ThemeStudioApp> createState() => _ThemeStudioAppState();
}

class _ThemeStudioAppState extends State<ThemeStudioApp> {
  final _inspector = GlobalKey<NodeInspectorState>();
  SceneEditor? _editor;
  late ThemeDefinition _theme;
  late String _path;
  String? _error;
  bool _dormant = false;
  bool _hasDraft = false;
  bool _confirmReload = false;

  @override
  void initState() {
    super.initState();
    _theme = widget.themeBuilder();
    _path = widget.scenePaths.first;
    _openScene(_path);
    unawaited(_loadSeed());
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
      _editor = editor..addListener(() => setState(() {}));
      _path = path;
      _error = null;
      _confirmReload = false;
      _hasDraft = false;
    } on Object catch (error) {
      _error = '$error';
    }
  }

  void _save() {
    if (_inspector.currentState?.apply() != true) return;
    try {
      _editor!.save();
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
        _hasDraft = false;
        _confirmReload = false;
      } on Object catch (error) {
        _error = '$error';
      }
    });
  }

  void _selectNode(String id) {
    if (_inspector.currentState?.apply() != true) return;
    _editor!.selectNode(id);
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
      theme: ThemeData(colorScheme: ColorSchemes.darkZinc, radius: 0.5),
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
                        Text(
                          _hasDraft || editor?.isDirty == true
                              ? 'Unsaved changes'
                              : 'Saved',
                        ).small().muted(),
                        const Gap(16),
                        OutlineButton(
                          onPressed: _hasDraft || editor?.canUndo == true
                              ? () {
                                  if (_inspector.currentState?.apply() ==
                                      true) {
                                    editor!.undo();
                                  }
                                }
                              : null,
                          child: const Text('Undo'),
                        ),
                        const Gap(8),
                        OutlineButton(
                          onPressed: editor?.canRedo == true
                              ? () {
                                  if (_inspector.currentState?.apply() ==
                                      true) {
                                    editor!.redo();
                                  }
                                }
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
                              for (final path in widget.scenePaths)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: GhostButton(
                                    onPressed: () {
                                      if (_inspector.currentState?.apply() ==
                                          false) {
                                        return;
                                      }
                                      if (_editor?.isDirty == true) {
                                        setState(
                                          () => _error = 'Save or reload your changes before switching scenes.',
                                        );
                                        return;
                                      }
                                      setState(() => _openScene(path));
                                    },
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
                              if (editor != null)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      OutlineButton(
                                        onPressed: () {
                                          if (_inspector.currentState!
                                              .apply()) {
                                            editor.duplicateSelectedNode();
                                          }
                                        },
                                        child: const Text('Duplicate node'),
                                      ),
                                      const Gap(8),
                                      OutlineButton(
                                        onPressed: editor.canDeleteNode
                                            ? () {
                                                if (_inspector.currentState!
                                                    .apply()) {
                                                  editor.deleteSelectedNode();
                                                }
                                              }
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
                                            theme: _theme,
                                            document: editor.document,
                                            selectedId: editor.selectedId,
                                            dormant: _dormant,
                                            onSelect: _selectNode,
                                          ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    editor == null
                                        ? 'Choose a valid scene document.'
                                        : '${editor.document.canvas.referenceWidth} × ${editor.document.canvas.referenceHeight}  ·  Click a node to inspect  ·  Simulated data',
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
                                  key: _inspector,
                                  node: editor.selectedNode,
                                  onUpdate: editor.updateNode,
                                  onDraftChanged: (value) =>
                                      setState(() => _hasDraft = value),
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
