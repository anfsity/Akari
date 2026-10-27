import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_component_assembly.dart';
import 'studio_assets.dart';
import 'studio_asset_preview.dart';
import 'studio_form.dart';

enum _SidebarTab {
  components('Compose'),
  layers('Layers'),
  assets('Assets');

  const _SidebarTab(this.label);
  final String label;
}

class StudioSidebar extends StatefulWidget {
  const StudioSidebar({
    required this.scenePaths,
    required this.assetPaths,
    required this.resolveAssetImage,
    required this.loadAssetText,
    required this.loadFontPreview,
    required this.onPlaceAsset,
    required this.onApplyFont,
    required this.editor,
    required this.loadingFile,
    required this.onLoadJson,
    required this.onSwitchScene,
    required this.onImportAsset,
    required this.onApplyBackground,
    this.readOnly = false,
    super.key,
  });

  final bool readOnly;
  final List<String> scenePaths;
  final List<String> assetPaths;
  final ImageProvider Function(String) resolveAssetImage;
  final SceneSvgLoader loadAssetText;
  final Future<String> Function(String) loadFontPreview;
  final ValueChanged<SceneAsset>? onPlaceAsset;
  final ValueChanged<String>? onApplyFont;
  final SceneEditor? editor;
  final bool loadingFile;
  final VoidCallback onLoadJson;
  final ValueChanged<String> onSwitchScene;
  final VoidCallback onImportAsset;
  final ValueChanged<String>? onApplyBackground;

  @override
  State<StudioSidebar> createState() => _StudioSidebarState();
}

class _StudioSidebarState extends State<StudioSidebar> {
  _SidebarTab? _tab;

  @override
  void didUpdateWidget(StudioSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editor != oldWidget.editor && _tab != _SidebarTab.assets) {
      _tab = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final tab =
        _tab ??
        (editor?.layout != null ||
                (editor?.presetCatalog.properties.isNotEmpty ?? false)
            ? _SidebarTab.components
            : _SidebarTab.layers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text('Scenes').small().muted(),
              const Spacer(),
              GhostButton(
                onPressed: widget.loadingFile ? null : widget.onLoadJson,
                density: ButtonDensity.compact,
                child: const Text('Load JSON').small(),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 90),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              for (final path in widget.scenePaths)
                Button(
                  key: ValueKey('scene-$path'),
                  style: editor?.file.path == path
                      ? const ButtonStyle.secondary()
                      : const ButtonStyle.ghost(),
                  onPressed: () => widget.onSwitchScene(path),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      File(path).uri.pathSegments.last,
                      overflow: TextOverflow.ellipsis,
                    ).small(),
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        if (editor != null)
          StudioLayoutCompleteness(editor: editor, readOnly: widget.readOnly),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Tabs(
            index: tab.index,
            expand: true,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            onChanged: (index) =>
                setState(() => _tab = _SidebarTab.values[index]),
            children: [
              for (final item in _SidebarTab.values)
                TabItem(
                  key: ValueKey('sidebar-${item.name}'),
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: tab == _SidebarTab.assets
              ? _AssetList(
                  paths: widget.assetPaths,
                  resolveImage: widget.resolveAssetImage,
                  loadText: widget.loadAssetText,
                  loadFont: widget.loadFontPreview,
                  onPlaceAsset: widget.readOnly ? null : widget.onPlaceAsset,
                  onApplyFont: widget.readOnly ? null : widget.onApplyFont,
                  loading: widget.loadingFile,
                  onImport: widget.readOnly ? null : widget.onImportAsset,
                  onApplyBackground: editor == null || widget.readOnly
                      ? null
                      : widget.onApplyBackground,
                )
              : editor == null
              ? const SizedBox()
              : tab == _SidebarTab.components
              ? StudioComponentAssembly(
                  editor: editor,
                  readOnly: widget.readOnly,
                )
              : _LayerList(
                  key: ObjectKey(editor),
                  editor: editor,
                  readOnly: widget.readOnly,
                ),
        ),
        if (tab == _SidebarTab.layers && editor != null) ...[
          const Divider(),
          _NodeActions(editor: editor, readOnly: widget.readOnly),
        ],
      ],
    );
  }
}

class _AssetList extends StatefulWidget {
  const _AssetList({
    required this.paths,
    required this.resolveImage,
    required this.loadText,
    required this.loadFont,
    required this.loading,
    required this.onImport,
    required this.onApplyBackground,
    required this.onPlaceAsset,
    required this.onApplyFont,
  });
  final List<String> paths;
  final ImageProvider Function(String) resolveImage;
  final SceneSvgLoader loadText;
  final Future<String> Function(String) loadFont;
  final bool loading;
  final VoidCallback? onImport;
  final ValueChanged<String>? onApplyBackground;
  final ValueChanged<SceneAsset>? onPlaceAsset;
  final ValueChanged<String>? onApplyFont;
  @override
  State<_AssetList> createState() => _AssetListState();
}

class _AssetListState extends State<_AssetList> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String? _selected;
  String _filter = 'all';
  String _query = '';
  int? _tint;
  @override
  void initState() {
    super.initState();
    _selected = widget.paths.firstOrNull;
  }

  @override
  void didUpdateWidget(_AssetList old) {
    super.didUpdateWidget(old);
    if (listEquals(widget.paths, old.paths)) return;
    final added = widget.paths.where((path) => !old.paths.contains(path));
    if (added.isNotEmpty) {
      _filter = 'all';
      _query = '';
      _search.clear();
    }
    _selected =
        added.firstOrNull ??
        (widget.paths.contains(_selected)
            ? _selected
            : _getPaths().firstOrNull);
    _tint = null;
    _scroll.jumpTo(0);
  }

  List<String> _getPaths() => widget.paths
      .where(
        (path) =>
            (_filter == 'all' || getStudioAssetKind(path).name == _filter) &&
            path.toLowerCase().contains(_query.toLowerCase()),
      )
      .toList();
  void _updateFilter(String filter) => setState(() {
    _filter = filter;
    _selected = _getPaths().firstOrNull;
    _tint = null;
  });
  void _updateSearch(String query) {
    if (query == _query) return;
    setState(() {
      _query = query;
      _selected = _getPaths().firstOrNull;
      _tint = null;
    });
  }

  void _selectAsset(String path) {
    setState(() {
      _selected = path;
      _tint = null;
    });
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _thumbnail(String path) {
    final kind = getStudioAssetKind(path);
    if (kind == StudioAssetKind.image ||
        kind == StudioAssetKind.material ||
        kind == StudioAssetKind.svg) {
      return StudioAssetSurface(
        child: SizedBox(
          width: 40,
          height: 40,
          child: SceneAssetView(
            asset: SceneAsset(
              path: path,
              kind: kind == StudioAssetKind.svg
                  ? SceneAssetKind.svg
                  : SceneAssetKind.image,
            ),
            resolveImage: widget.resolveImage,
            loadSvg: widget.loadText,
          ),
        ),
      );
    }
    return SizedBox(
      width: 40,
      height: 40,
      child: Icon(switch (kind) {
        StudioAssetKind.font => LucideIcons.type,
        StudioAssetKind.audio => LucideIcons.volume2,
        StudioAssetKind.shader => LucideIcons.sparkles,
        _ => LucideIcons.file,
      }, size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final kind = selected == null ? null : getStudioAssetKind(selected);
    final raster =
        kind == StudioAssetKind.image || kind == StudioAssetKind.material;
    final paths = _getPaths();
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlineButton(
                  onPressed: widget.loading ? null : widget.onImport,
                  child: const Text('Import asset'),
                ),
                const Gap(8),
                TextField(
                  key: const ValueKey('asset-search'),
                  controller: _search,
                  placeholder: const Text('Search assets'),
                  onChanged: _updateSearch,
                ),
                const Gap(8),
                StudioSelect<String>(
                  key: const ValueKey('asset-category'),
                  value: _filter,
                  values: [
                    'all',
                    for (final kind in StudioAssetKind.values) kind.name,
                  ],
                  formatValue: (value) => switch (value) {
                    'all' => 'All assets',
                    'image' => 'Images',
                    'svg' => 'SVG icons',
                    'font' => 'Fonts',
                    'material' => 'Materials & textures',
                    'audio' => 'Audio',
                    'shader' => 'Shaders',
                    _ => 'Other files',
                  },
                  onChanged: _updateFilter,
                ),
                if (selected != null) ...[
                  const Gap(12),
                  Text(
                    selected.split('/').last,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ).small().semiBold(),
                  const Gap(8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OutlineButton(
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: selected)),
                        child: const Text('Copy path').small(),
                      ),
                      if (kind == StudioAssetKind.font)
                        PrimaryButton(
                          key: const ValueKey('apply-asset-font'),
                          onPressed: widget.onApplyFont == null
                              ? null
                              : () => widget.onApplyFont!(selected),
                          child: const Text('Apply to selection').small(),
                        ),
                      if (raster)
                        PrimaryButton(
                          onPressed: widget.onApplyBackground == null
                              ? null
                              : () => widget.onApplyBackground!(selected),
                          child: const Text('Use image').small(),
                        ),
                      if (raster || kind == StudioAssetKind.svg)
                        OutlineButton(
                          key: const ValueKey('place-asset'),
                          onPressed: widget.onPlaceAsset == null
                              ? null
                              : () => widget.onPlaceAsset!(
                                  SceneAsset(
                                    path: selected,
                                    kind: kind == StudioAssetKind.svg
                                        ? SceneAssetKind.svg
                                        : SceneAssetKind.image,
                                    tint: _tint,
                                  ),
                                ),
                          child: const Text('Add to canvas').small(),
                        ),
                    ],
                  ),
                  const Gap(12),
                  if (kind == StudioAssetKind.svg) ...[
                    Row(
                      children: [
                        Expanded(
                          child: const Text('Override icon color').small(),
                        ),
                        Switch(
                          value: _tint != null,
                          onChanged: (enabled) => setState(
                            () => _tint = enabled ? 0xffffffff : null,
                          ),
                        ),
                      ],
                    ),
                    if (_tint != null)
                      ColorInput(
                        key: const ValueKey('asset-tint'),
                        value: ColorDerivative.fromColor(Color(_tint!)),
                        onChanging: (value) =>
                            setState(() => _tint = value.toColor().toARGB32()),
                        onChanged: (value) =>
                            setState(() => _tint = value.toColor().toARGB32()),
                      ),
                    const Gap(8),
                  ],
                  StudioAssetPreview(
                    path: selected,
                    resolveImage: widget.resolveImage,
                    loadText: widget.loadText,
                    loadFont: widget.loadFont,
                    tint: _tint,
                  ),
                  const Gap(12),
                  const Divider(),
                ],
                if (paths.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      widget.paths.isEmpty
                          ? 'Import images, fonts and files for this theme.'
                          : 'No matching assets.',
                    ).small().muted(),
                  ),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: paths.length,
          itemBuilder: (context, index) {
            final path = paths[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Button(
                key: ValueKey('asset-$path'),
                style: path == selected
                    ? const ButtonStyle.secondary()
                    : const ButtonStyle.ghost(),
                onPressed: () => _selectAsset(path),
                child: Row(
                  children: [
                    _thumbnail(path),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        path.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).small(),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Fixed-height rows let canvas selection reveal a layer even when its row
/// has not been built. Only a changed selection moves the user's scroll view.
class _LayerList extends StatefulWidget {
  const _LayerList({required this.editor, required this.readOnly, super.key});

  final bool readOnly;

  final SceneEditor editor;

  @override
  State<_LayerList> createState() => _LayerListState();
}

class _LayerListState extends State<_LayerList> {
  static const _rowHeight = 36.0;
  final _scroll = ScrollController();
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.editor.selectedId;
    widget.editor.addListener(_revealChangedSelection);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelection());
  }

  void _revealChangedSelection() {
    if (_selectedId == widget.editor.selectedId) return;
    _selectedId = widget.editor.selectedId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelection());
  }

  void _revealSelection() {
    if (!mounted || !_scroll.hasClients) return;
    final nodes = widget.editor.document.layerOrder;
    final top = nodes.indexWhere((node) => node.id == _selectedId) * _rowHeight;
    final bottom = top + _rowHeight;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        math.min(bottom - position.viewportDimension, position.maxScrollExtent),
      );
    }
  }

  @override
  void dispose() {
    widget.editor.removeListener(_revealChangedSelection);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.editor,
    builder: (context, _) {
      final nodes = widget.editor.document.layerOrder;
      return ListView.builder(
        key: const ValueKey('layer-list'),
        controller: _scroll,
        itemExtent: _rowHeight,
        itemCount: nodes.length + 1,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemBuilder: (context, index) {
          if (index == nodes.length) {
            return DragTarget<String>(
              onWillAcceptWithDetails: (_) => !widget.readOnly,
              onAcceptWithDetails: (details) =>
                  widget.editor.moveLayer(details.data, parentId: null),
              builder: (context, candidates, _) => Container(
                key: const ValueKey('layer-root-drop'),
                alignment: Alignment.centerLeft,
                color: candidates.isEmpty
                    ? null
                    : Theme.of(context).colorScheme.secondary,
                child: const Text('Move to scene root').small().muted(),
              ),
            );
          }
          final node = nodes[index];
          final selected = widget.editor.selectedIds.contains(node.id);
          var depth = 0;
          var parentId = node.parentId;
          while (parentId != null) {
            depth++;
            parentId = nodes.firstWhere((node) => node.id == parentId).parentId;
          }
          final label =
              widget.editor.layout?.findSlot(node.id)?.label ?? node.id;
          return _LayerRow(
            editor: widget.editor,
            node: node,
            label: label,
            depth: depth,
            selected: selected,
            readOnly: widget.readOnly,
          );
        },
      );
    },
  );
}

class _NodeActions extends StatelessWidget {
  const _NodeActions({required this.editor, required this.readOnly});

  final SceneEditor editor;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editor,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlineButton(
                  density: ButtonDensity.dense,
                  onPressed: !readOnly && editor.canDuplicateNode
                      ? editor.duplicateSelectedNode
                      : null,
                  child: const Text('Duplicate', maxLines: 1).small(),
                ),
              ),
              const Gap(8),
              Expanded(
                child: OutlineButton(
                  density: ButtonDensity.dense,
                  onPressed: !readOnly && editor.canDeleteNode
                      ? editor.deleteSelectedNode
                      : null,
                  child: const Text('Delete', maxLines: 1).small(),
                ),
              ),
            ],
          ),
          if (editor.deletionBlockReason case final reason?) ...[
            const Gap(8),
            Text(reason).small().muted(),
          ],
          if (!editor.canDuplicateNode) ...[
            const Gap(8),
            const Text('Layout components can only be added once.')
                .small()
                .muted(),
          ],
        ],
      ),
    ),
  );
}

class _LayerRow extends StatefulWidget {
  const _LayerRow({
    required this.editor,
    required this.node,
    required this.label,
    required this.depth,
    required this.selected,
    required this.readOnly,
  });
  final SceneEditor editor;
  final SceneNode node;
  final String label;
  final int depth;
  final bool selected;
  final bool readOnly;
  @override
  State<_LayerRow> createState() => _LayerRowState();
}

class _LayerRowState extends State<_LayerRow> {
  int _zone = 0;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      return DragTarget<String>(
        onWillAcceptWithDetails: (details) =>
            !widget.readOnly && details.data != widget.node.id,
        onMove: (details) {
          final box = context.findRenderObject()! as RenderBox;
          final y =
              box.globalToLocal(details.offset).dy / constraints.maxHeight;
          final zone = widget.node.layout != null && y > .25 && y < .75
              ? 0
              : y < .5
              ? -1
              : 1;
          if (zone != _zone) setState(() => _zone = zone);
        },
        onAcceptWithDetails: (details) {
          if (_zone == 0 && widget.node.layout != null) {
            widget.editor.moveLayer(details.data, parentId: widget.node.id);
            return;
          }
          final siblings = widget.editor.document
              .getChildren(widget.node.parentId)
              .reversed
              .where((node) => node.id != details.data)
              .toList();
          final index = siblings.indexWhere(
            (node) => node.id == widget.node.id,
          );
          final before = _zone < 0
              ? widget.node.id
              : index + 1 < siblings.length
              ? siblings[index + 1].id
              : null;
          widget.editor.moveLayer(
            details.data,
            parentId: widget.node.parentId,
            beforeId: before,
          );
        },
        builder: (context, candidates, _) => Container(
          decoration: BoxDecoration(
            color: candidates.isNotEmpty && _zone == 0
                ? colors.secondary
                : null,
            border: Border(
              top: BorderSide(
                color: candidates.isNotEmpty && _zone < 0
                    ? colors.primary
                    : Colors.transparent,
              ),
              bottom: BorderSide(
                color: candidates.isNotEmpty && _zone > 0
                    ? colors.primary
                    : Colors.transparent,
              ),
            ),
          ),
          child: Draggable<String>(
            data: widget.node.id,
            affinity: Axis.horizontal,
            maxSimultaneousDrags: widget.readOnly ? 0 : 1,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: Container(
              padding: const EdgeInsets.all(8),
              color: colors.background,
              child: Text(widget.label),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Button(
                key: ValueKey('layer-${widget.node.id}'),
                style: widget.selected
                    ? const ButtonStyle.secondary(density: ButtonDensity.dense)
                    : const ButtonStyle.ghost(density: ButtonDensity.dense),
                onPressed: () => widget.editor.selectNode(
                  widget.node.id,
                  toggle: HardwareKeyboard.instance.isShiftPressed,
                ),
                child: Row(
                  children: [
                    SizedBox(width: widget.depth * 12),
                    Icon(
                      widget.node.layout == null
                          ? LucideIcons.layers
                          : LucideIcons.frame,
                      size: 14,
                    ),
                    const Gap(8),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).small(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
