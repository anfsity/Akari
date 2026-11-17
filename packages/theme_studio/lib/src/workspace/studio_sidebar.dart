import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../authoring/studio_component_assembly.dart';
import '../resources/studio_assets.dart';
import '../resources/studio_asset_preview.dart';
import '../inspector/studio_form.dart';

AbstractButtonStyle _getSelectableRowStyle(
  ColorScheme colors, {
  required bool selected,
  ButtonDensity density = ButtonDensity.normal,
}) {
  return ButtonStyle.ghost(density: density).copyWith(
    decoration: (context, states, value) => (value as BoxDecoration).copyWith(
      color: selected ? colors.primary.withValues(alpha: 0.08) : null,
      border: selected
          ? Border.all(color: colors.primary.withValues(alpha: 0.25))
          : null,
    ),
  );
}

enum _SidebarTab {
  components('Compose'),
  layers('Layers'),
  assets('Assets');

  const _SidebarTab(this.label);
  final String label;
}

class StudioSidebar extends StatefulWidget {
  const StudioSidebar({
    required this.assetPaths,
    required this.resolveAssetImage,
    required this.loadAssetText,
    required this.loadFontPreview,
    required this.onPlaceAsset,
    required this.onApplyFont,
    required this.editor,
    required this.loadingFile,
    required this.onImportAsset,
    required this.onApplyBackground,
    this.readOnly = false,
    super.key,
  });

  final bool readOnly;
  final List<String> assetPaths;
  final ImageProvider Function(String) resolveAssetImage;
  final SceneSvgLoader loadAssetText;
  final Future<String> Function(String) loadFontPreview;
  final ValueChanged<SceneAsset>? onPlaceAsset;
  final ValueChanged<String>? onApplyFont;
  final SceneEditor? editor;
  final bool loadingFile;
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
        if (editor != null)
          StudioLayoutCompleteness(editor: editor, readOnly: widget.readOnly),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.label,
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
    if (_scroll.hasClients) _scroll.jumpTo(0);
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
    if (!_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
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
                _AssetSearchHeader(
                  searchController: _search,
                  filter: _filter,
                  loading: widget.loading,
                  onImport: widget.onImport,
                  onSearchChanged: _updateSearch,
                  onFilterChanged: _updateFilter,
                ),
                if (selected != null) ...[
                  const Gap(12),
                  _SelectedAssetPanel(
                    path: selected,
                    tint: _tint,
                    resolveImage: widget.resolveImage,
                    loadText: widget.loadText,
                    loadFont: widget.loadFont,
                    onApplyFont: widget.onApplyFont,
                    onApplyBackground: widget.onApplyBackground,
                    onPlaceAsset: widget.onPlaceAsset,
                    onTintChanged: (tint) => setState(() => _tint = tint),
                  ),
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
            return _AssetRow(
              path: path,
              selected: path == selected,
              resolveImage: widget.resolveImage,
              loadText: widget.loadText,
              onSelect: () => _selectAsset(path),
            );
          },
        ),
      ],
    );
  }
}

class _AssetSearchHeader extends StatelessWidget {
  const _AssetSearchHeader({
    required this.searchController,
    required this.filter,
    required this.loading,
    required this.onImport,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  final TextEditingController searchController;
  final String filter;
  final bool loading;
  final VoidCallback? onImport;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterChanged;

  static String _formatCategory(String value) => switch (value) {
    'all' => 'All assets',
    'image' => 'Images',
    'svg' => 'SVG icons',
    'font' => 'Fonts',
    'material' => 'Materials & textures',
    'audio' => 'Audio',
    'shader' => 'Shaders',
    _ => 'Other files',
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlineButton(
        onPressed: loading ? null : onImport,
        child: const Text('Import asset'),
      ),
      const Gap(8),
      TextField(
        key: const ValueKey('asset-search'),
        controller: searchController,
        placeholder: const Text('Search assets'),
        onChanged: onSearchChanged,
      ),
      const Gap(8),
      StudioSelect<String>(
        key: const ValueKey('asset-category'),
        value: filter,
        values: ['all', for (final kind in StudioAssetKind.values) kind.name],
        formatValue: _formatCategory,
        onChanged: onFilterChanged,
      ),
    ],
  );
}

class _SelectedAssetPanel extends StatelessWidget {
  const _SelectedAssetPanel({
    required this.path,
    required this.tint,
    required this.resolveImage,
    required this.loadText,
    required this.loadFont,
    required this.onApplyFont,
    required this.onApplyBackground,
    required this.onPlaceAsset,
    required this.onTintChanged,
  });

  final String path;
  final int? tint;
  final ImageProvider Function(String) resolveImage;
  final SceneSvgLoader loadText;
  final Future<String> Function(String) loadFont;
  final ValueChanged<String>? onApplyFont;
  final ValueChanged<String>? onApplyBackground;
  final ValueChanged<SceneAsset>? onPlaceAsset;
  final ValueChanged<int?> onTintChanged;

  @override
  Widget build(BuildContext context) {
    final kind = getStudioAssetKind(path);
    final raster =
        kind == StudioAssetKind.image || kind == StudioAssetKind.material;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          path.split('/').last,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ).small().semiBold(),
        const Gap(8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlineButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: path)),
              child: const Text('Copy path').small(),
            ),
            if (kind == StudioAssetKind.font)
              PrimaryButton(
                key: const ValueKey('apply-asset-font'),
                onPressed: onApplyFont == null
                    ? null
                    : () => onApplyFont!(path),
                child: const Text('Apply font').small(),
              ),
            if (raster)
              PrimaryButton(
                onPressed: onApplyBackground == null
                    ? null
                    : () => onApplyBackground!(path),
                child: const Text('Use image').small(),
              ),
            if (raster || kind == StudioAssetKind.svg)
              OutlineButton(
                key: const ValueKey('place-asset'),
                onPressed: onPlaceAsset == null
                    ? null
                    : () => onPlaceAsset!(
                        SceneAsset(
                          path: path,
                          kind: kind == StudioAssetKind.svg
                              ? SceneAssetKind.svg
                              : SceneAssetKind.image,
                          tint: tint,
                        ),
                      ),
                child: const Text('Add to canvas').small(),
              ),
          ],
        ),
        const Gap(12),
        if (kind == StudioAssetKind.svg) ...[
          StudioSwitchRow(
            label: 'Override icon color',
            value: tint != null,
            onChanged: (enabled) => onTintChanged(enabled ? 0xffffffff : null),
          ),
          if (tint case final activeTint?) ...[
            const Gap(8),
            ColorInput(
              key: const ValueKey('asset-tint'),
              value: ColorDerivative.fromColor(Color(activeTint)),
              onChanging: (value) => onTintChanged(value.toColor().toARGB32()),
              onChanged: (value) => onTintChanged(value.toColor().toARGB32()),
            ),
          ],
          const Gap(8),
        ],
        StudioAssetPreview(
          path: path,
          resolveImage: resolveImage,
          loadText: loadText,
          loadFont: loadFont,
          tint: tint,
        ),
        const Gap(12),
        const Divider(),
      ],
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.path,
    required this.selected,
    required this.resolveImage,
    required this.loadText,
    required this.onSelect,
  });

  final String path;
  final bool selected;
  final ImageProvider Function(String) resolveImage;
  final SceneSvgLoader loadText;
  final VoidCallback onSelect;

  Widget _buildThumbnail() {
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
            resolveImage: resolveImage,
            loadSvg: loadText,
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
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Button(
        key: ValueKey('asset-$path'),
        style: _getSelectableRowStyle(colors, selected: selected),
        onPressed: onSelect,
        child: Row(
          children: [
            _buildThumbnail(),
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
  bool _dragging = false;

  void _updateDragging(bool dragging) {
    if (mounted && _dragging != dragging) {
      setState(() => _dragging = dragging);
    }
  }

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
      final depths = _calculateLayerDepths(nodes);
      return ListView.builder(
        key: const ValueKey('layer-list'),
        controller: _scroll,
        itemExtent: _rowHeight,
        itemCount: nodes.length + 1,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemBuilder: (context, index) {
          if (index == nodes.length) {
            return _LayerRootDropTarget(
              dragging: _dragging,
              readOnly: widget.readOnly,
              onDrop: (nodeId) =>
                  widget.editor.moveLayer(nodeId, parentId: null),
            );
          }
          final node = nodes[index];
          return _LayerRow(
            editor: widget.editor,
            node: node,
            label: widget.editor.layout?.findSlot(node.id)?.label ?? node.id,
            depth: depths[node.id] ?? 0,
            selected: widget.editor.selectedIds.contains(node.id),
            readOnly: widget.readOnly,
            onDragChanged: _updateDragging,
          );
        },
      );
    },
  );
}

Map<String, int> _calculateLayerDepths(List<SceneNode> nodes) {
  final parentById = {for (final node in nodes) node.id: node.parentId};
  final depths = <String, int>{};
  int resolveDepth(String id) {
    if (depths[id] case final cached?) return cached;
    final parentId = parentById[id];
    final depth = parentId == null ? 0 : resolveDepth(parentId) + 1;
    depths[id] = depth;
    return depth;
  }

  for (final node in nodes) {
    resolveDepth(node.id);
  }
  return depths;
}

class _LayerRootDropTarget extends StatelessWidget {
  const _LayerRootDropTarget({
    required this.dragging,
    required this.readOnly,
    required this.onDrop,
  });

  final bool dragging;
  final bool readOnly;
  final ValueChanged<String> onDrop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => !readOnly,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, _) {
        final active = dragging || candidates.isNotEmpty;
        return Container(
          key: const ValueKey('layer-root-drop'),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: !active
              ? null
              : BoxDecoration(
                  color: candidates.isEmpty
                      ? colors.muted.withValues(alpha: 0.45)
                      : colors.secondary,
                  border: Border.all(
                    color: candidates.isEmpty ? colors.border : colors.primary,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
          child: !active
              ? null
              : Row(
                  children: [
                    Icon(
                      LucideIcons.cornerLeftUp,
                      size: 13,
                      color: colors.mutedForeground,
                    ),
                    const Gap(6),
                    Expanded(
                      child: const Text(
                        'Move to scene root',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).xSmall().muted(),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _NodeActions extends StatelessWidget {
  const _NodeActions({required this.editor, required this.readOnly});

  final SceneEditor editor;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editor,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 34),
            child: Row(
              spacing: 8,
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
          ),
          if (editor.deletionBlockReason case final reason?)
            Text(reason).xSmall().muted(),
          if (!editor.canDuplicateNode)
            const Text('Layout components can only be added once.')
                .xSmall()
                .muted(),
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
    required this.onDragChanged,
  });
  final SceneEditor editor;
  final SceneNode node;
  final String label;
  final int depth;
  final bool selected;
  final bool readOnly;
  final ValueChanged<bool> onDragChanged;
  @override
  State<_LayerRow> createState() => _LayerRowState();
}

class _LayerRowState extends State<_LayerRow> {
  int _zone = 0;

  void _updateDropZone(Offset globalOffset, double height) {
    final box = context.findRenderObject()! as RenderBox;
    final y = box.globalToLocal(globalOffset).dy / height;
    final zone = widget.node.layout != null && y > .25 && y < .75
        ? 0
        : y < .5
        ? -1
        : 1;
    if (zone != _zone) setState(() => _zone = zone);
  }

  void _handleDrop(String draggedId) {
    if (_zone == 0 && widget.node.layout != null) {
      widget.editor.moveLayer(draggedId, parentId: widget.node.id);
      return;
    }
    final siblings = widget.editor.document
        .getChildren(widget.node.parentId)
        .reversed
        .where((node) => node.id != draggedId)
        .toList();
    final index = siblings.indexWhere((node) => node.id == widget.node.id);
    final before = _zone < 0
        ? widget.node.id
        : index + 1 < siblings.length
        ? siblings[index + 1].id
        : null;
    widget.editor.moveLayer(
      draggedId,
      parentId: widget.node.parentId,
      beforeId: before,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      return DragTarget<String>(
        onWillAcceptWithDetails: (details) =>
            !widget.readOnly && details.data != widget.node.id,
        onMove: (details) =>
            _updateDropZone(details.offset, constraints.maxHeight),
        onAcceptWithDetails: (details) => _handleDrop(details.data),
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
            onDragStarted: () => widget.onDragChanged(true),
            onDragEnd: (_) => widget.onDragChanged(false),
            onDraggableCanceled: (_, _) => widget.onDragChanged(false),
            feedback: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.background,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 8),
                ],
              ),
              child: Text(widget.label).small(),
            ),
            child: _LayerRowButton(
              node: widget.node,
              label: widget.label,
              depth: widget.depth,
              selected: widget.selected,
              onPressed: () => widget.editor.selectNode(
                widget.node.id,
                toggle: HardwareKeyboard.instance.isShiftPressed,
              ),
            ),
          ),
        ),
      );
    },
  );
}

IconData _getLayerIcon(SceneNode node) {
  if (node.layout != null) return LucideIcons.frame;
  if (node.asset != null) return LucideIcons.image;
  return switch (node.primitive) {
    ScenePrimitive.text => LucideIcons.type,
    ScenePrimitive.rectangle => LucideIcons.square,
    ScenePrimitive.circle => LucideIcons.circle,
    null => LucideIcons.component,
  };
}

class _LayerRowButton extends StatelessWidget {
  const _LayerRowButton({
    required this.node,
    required this.label,
    required this.depth,
    required this.selected,
    required this.onPressed,
  });

  final SceneNode node;
  final String label;
  final int depth;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Button(
        key: ValueKey('layer-${node.id}'),
        style: _getSelectableRowStyle(
          colors,
          selected: selected,
          density: ButtonDensity.dense,
        ),
        onPressed: onPressed,
        child: Row(
          children: [
            SizedBox(width: depth * 12),
            Icon(
              _getLayerIcon(node),
              size: 14,
              color: selected ? colors.primary : colors.mutedForeground,
            ),
            const Gap(8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ).small(),
            ),
            if (node.tracks.isNotEmpty) ...[
              const Gap(4),
              Icon(LucideIcons.film, size: 12, color: colors.mutedForeground),
            ],
            if (node.visibleWhen != null ||
                node.stateEffects.isNotEmpty ||
                node.transitions.isNotEmpty) ...[
              const Gap(4),
              Icon(
                LucideIcons.gitBranch,
                size: 12,
                color: colors.mutedForeground,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
