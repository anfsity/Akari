import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../resources/studio_asset_preview.dart';
import '../resources/studio_assets.dart';
import '../ui/studio_form.dart';

class StudioAssetBrowser extends StatefulWidget {
  const StudioAssetBrowser({
    required this.paths,
    required this.resolveImage,
    required this.loadText,
    required this.loadFont,
    required this.loading,
    required this.onImport,
    required this.onApplyBackground,
    required this.onPlaceAsset,
    required this.onApplyFont,
    super.key,
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
  State<StudioAssetBrowser> createState() => _StudioAssetBrowserState();
}

class _StudioAssetBrowserState extends State<StudioAssetBrowser> {
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
  void didUpdateWidget(StudioAssetBrowser old) {
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
        style: getStudioSelectableRowStyle(colors, selected: selected),
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
