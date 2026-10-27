import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'scene_editor.dart';
import 'studio_component_assembly.dart';

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
              : _LayerList(key: ObjectKey(editor), editor: editor),
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
    required this.loading,
    required this.onImport,
    required this.onApplyBackground,
  });

  final List<String> paths;
  final ImageProvider Function(String) resolveImage;
  final bool loading;
  final VoidCallback? onImport;
  final ValueChanged<String>? onApplyBackground;

  @override
  State<_AssetList> createState() => _AssetListState();
}

class _AssetListState extends State<_AssetList> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.paths.firstOrNull;
  }

  @override
  void didUpdateWidget(_AssetList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.paths, oldWidget.paths) ||
        listEquals(widget.paths, oldWidget.paths)) {
      return;
    }
    final added = widget.paths.where((path) => !oldWidget.paths.contains(path));
    _selected =
        added.firstOrNull ??
        (widget.paths.contains(_selected)
            ? _selected
            : widget.paths.firstOrNull);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: OutlineButton(
            onPressed: widget.loading ? null : widget.onImport,
            child: const Text('Import asset'),
          ),
        ),
        Expanded(
          child: widget.paths.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: const Text('Import images and files for this theme.')
                      .small()
                      .muted(),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: widget.paths.length,
                  itemBuilder: (context, index) {
                    final asset = widget.paths[index];
                    return Button(
                      style: asset == selected
                          ? const ButtonStyle.secondary()
                          : const ButtonStyle.ghost(),
                      onPressed: () => setState(() => _selected = asset),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image(
                              image: widget.resolveImage(asset),
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Icon(LucideIcons.file, size: 20),
                                  ),
                            ),
                          ),
                          const Gap(10),
                          Expanded(
                            child: Text(
                              asset.split('/').last,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ).small(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (selected != null) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  selected.split('/').last,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ).small().muted(),
                const Gap(8),
                OutlineButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: selected)),
                  child: const Text('Copy path'),
                ),
                const Gap(8),
                PrimaryButton(
                  onPressed: widget.onApplyBackground == null
                      ? null
                      : () => widget.onApplyBackground!(selected),
                  child: const Text('Use image'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Fixed-height rows let canvas selection reveal a layer even when its row
/// has not been built. Only a changed selection moves the user's scroll view.
class _LayerList extends StatefulWidget {
  const _LayerList({required this.editor, super.key});

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
        itemCount: nodes.length,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemBuilder: (context, index) {
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
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Button(
              key: ValueKey('layer-${node.id}'),
              style: selected
                  ? const ButtonStyle.secondary(density: ButtonDensity.dense)
                  : const ButtonStyle.ghost(density: ButtonDensity.dense),
              onPressed: () => widget.editor.selectNode(
                node.id,
                toggle: HardwareKeyboard.instance.isShiftPressed,
              ),
              child: Row(
                children: [
                  SizedBox(width: depth * 12),
                  Icon(
                    LucideIcons.layers,
                    size: 14,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.mutedForeground,
                  ),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).small(),
                  ),
                ],
              ),
            ),
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
