import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../authoring/studio_component_assembly.dart';
import '../ui/studio_form.dart';
import 'studio_asset_browser.dart';

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
              ? StudioAssetBrowser(
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
        style: getStudioSelectableRowStyle(
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
