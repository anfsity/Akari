import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'studio_preferences.dart';
import 'studio_form.dart';
import 'studio_form_values.dart';
import 'studio_theme.dart';

class StudioSettings extends StatefulWidget {
  const StudioSettings({
    required this.document,
    required this.preferences,
    required this.assetPaths,
    required this.resolveAssetImage,
    required this.onApply,
    super.key,
  });

  final SceneDocument document;
  final StudioPreferences preferences;
  final List<String> assetPaths;
  final ImageProvider Function(String) resolveAssetImage;
  final void Function(SceneCanvas, SceneBackground, StudioPreferences) onApply;

  @override
  State<StudioSettings> createState() => _StudioSettingsState();
}

enum _SettingsSection {
  canvas('Canvas', LucideIcons.scan, 'Reference size and scene layout'),
  background('Background', LucideIcons.image, 'Color, image, and atmosphere'),
  appearance(
    'Appearance',
    LucideIcons.palette,
    'Make the editor feel like yours',
  ),
  grid(
    'Grid & snapping',
    LucideIcons.grid2x2,
    'Precision while moving and resizing',
  );

  const _SettingsSection(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;

  bool get isSceneSetting => this == canvas || this == background;
}

enum _CanvasPreset {
  hd('HD', 1280, 720),
  fullHd('Full HD', 1920, 1080),
  qhd('QHD', 2560, 1440),
  uhd('4K UHD', 3840, 2160),
  portrait('Portrait', 1080, 1920);

  const _CanvasPreset(this.label, this.width, this.height);

  final String label;
  final int width;
  final int height;
}

/// Drafts live for the dialog, independently of the selected category. Apply
/// hands the complete draft to the scene editor so validation and undo keep
/// using the same document boundary as canvas and inspector edits.
class _StudioSettingsState extends State<StudioSettings> {
  final _fields = <String, TextEditingController>{};
  _SettingsSection _section = _SettingsSection.canvas;
  late SceneCanvasFit _fit;
  late SceneBackgroundKind _background;
  late bool _safeArea;
  late ThemeMode _themeMode;
  late StudioPalette _palette;
  late bool _showGrid;
  late bool _snapToGrid;
  String? _error;
  _SettingsSection? _errorSection;

  @override
  void initState() {
    super.initState();
    final scene = widget.document;
    final preferences = widget.preferences;
    final values = {
      'Canvas width': '${scene.canvas.referenceWidth}',
      'Canvas height': '${scene.canvas.referenceHeight}',
      'Background color': encodeSceneColor(scene.background.color),
      'Background asset': scene.background.asset ?? '',
      'Background blur': '${scene.background.blurSigma}',
      'Scrim opacity': '${scene.background.scrimOpacity}',
      'Grid size (pixels)': '${preferences.gridSize}',
    };
    for (final entry in values.entries) {
      _fields[entry.key] = TextEditingController(text: entry.value);
    }
    _fit = scene.canvas.fit;
    _safeArea = scene.canvas.useSafeArea;
    _background = scene.background.kind;
    _themeMode = preferences.themeMode;
    _palette = preferences.palette;
    _showGrid = preferences.showGrid;
    _snapToGrid = preferences.snapToGrid;
  }

  int _getInteger(String label) => getIntegerInput(label, _fields[label]!.text);

  double _getNumber(String label) =>
      getFiniteNumberInput(label, _fields[label]!.text);

  SceneCanvas _getCanvas() => widget.document.canvas.copyWith(
    referenceWidth: _getInteger('Canvas width'),
    referenceHeight: _getInteger('Canvas height'),
    fit: _fit,
    useSafeArea: _safeArea,
  );

  SceneBackground _getBackground() {
    final asset = _fields['Background asset']!.text.trim();
    if (_background == SceneBackgroundKind.image && asset.isEmpty) {
      throw const FormatException('Choose or import a background image first.');
    }
    return SceneBackground(
      kind: _background,
      asset: asset.isEmpty ? null : asset,
      color: decodeSceneColor(_fields['Background color']!.text.trim()),
      blurSigma: _getNumber('Background blur'),
      scrimOpacity: _getNumber('Scrim opacity'),
      rendererId: widget.document.background.rendererId,
    );
  }

  StudioPreferences _getPreferences() {
    final gridSize = _getInteger('Grid size (pixels)');
    StudioPreferences.validateGridSize(gridSize);
    return StudioPreferences(
      themeMode: _themeMode,
      palette: _palette,
      showGrid: _showGrid,
      snapToGrid: _snapToGrid,
      gridSize: gridSize,
    );
  }

  void _apply() {
    // Parsing errors belong to the category being read. Codec errors returned
    // by the editor name canvas/background; bring that category into view too.
    var errorSection = _SettingsSection.canvas;
    try {
      final canvas = _getCanvas();
      errorSection = _SettingsSection.background;
      final background = _getBackground();
      errorSection = _SettingsSection.grid;
      final preferences = _getPreferences();
      errorSection = _SettingsSection.canvas;
      widget.onApply(canvas, background, preferences);
      Navigator.of(context).pop();
    } on FormatException catch (error) {
      final message = error.message.toLowerCase();
      setState(() {
        _section = message.contains('background')
            ? _SettingsSection.background
            : message.contains('canvas')
            ? _SettingsSection.canvas
            : errorSection;
        _error = error.message;
        _errorSection = _section;
      });
    }
  }

  _CanvasPreset? _findPreset() {
    final width = int.tryParse(_fields['Canvas width']!.text);
    final height = int.tryParse(_fields['Canvas height']!.text);
    return _CanvasPreset.values
        .where((preset) => preset.width == width && preset.height == height)
        .firstOrNull;
  }

  Color? _getBackgroundColor() {
    try {
      return Color(decodeSceneColor(_fields['Background color']!.text.trim()));
    } on FormatException {
      return null;
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final colors = Theme.of(context).colorScheme;
    final width = math.min(820.0, size.width - 48);
    final compact = width < 620;
    return ModalBackdrop(
      theme: ModalBackdropTheme(
        borderRadius: BorderRadius.circular(12),
        barrierColor: Colors.black.withValues(alpha: 0.35),
      ),
      child: ModalContainer(
        filled: true,
        fillColor: colors.background,
        borderColor: colors.border,
        borderWidth: 1,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsets.zero,
        child: SizedBox(
          key: const ValueKey('studio-settings'),
          width: width,
          height: math.min(640.0, size.height - 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.settings2, size: 20),
                    const Gap(12),
                    const Text('Studio settings').large().semiBold(),
                  ],
                ),
              ),
              const Divider(),
              if (compact) _buildNavigation(horizontal: true),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!compact)
                      SizedBox(
                        width: 184,
                        child: _buildNavigation(horizontal: false),
                      ),
                    if (!compact) const VerticalDivider(),
                    Expanded(
                      child: SingleChildScrollView(
                        key: ValueKey('settings-page-${_section.name}'),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_section.label).large().semiBold(),
                            const Gap(4),
                            Text(_section.description).small().muted(),
                            const Gap(20),
                            if (_errorSection == _section &&
                                _error != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colors.destructive.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: StudioFormError(_error!),
                              ),
                              const Gap(16),
                            ],
                            switch (_section) {
                              _SettingsSection.canvas => _buildCanvasSection(),
                              _SettingsSection.background =>
                                _buildBackgroundSection(),
                              _SettingsSection.appearance =>
                                _buildAppearanceSection(),
                              _SettingsSection.grid => _buildGridSection(),
                            },
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    if (!compact) ...[
                      Expanded(
                        child: Text(
                          _section.isSceneSetting
                              ? 'Scene changes can be undone.\nSave scene to write them to disk.'
                              : 'Editor preferences are saved when applied.\nYour theme appearance stays the same.',
                        ).small().muted(),
                      ),
                      const Gap(16),
                    ] else
                      const Spacer(),
                    OutlineButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const Gap(8),
                    PrimaryButton(
                      onPressed: _apply,
                      child: const Text('Apply settings'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigation({required bool horizontal}) {
    final buttons = [
      for (final section in _SettingsSection.values)
        Button(
          key: ValueKey('settings-nav-${section.name}'),
          style: _section == section
              ? const ButtonStyle.secondary()
              : const ButtonStyle.ghost(),
          onPressed: () => setState(() => _section = section),
          child: Row(
            mainAxisSize: horizontal ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Icon(section.icon, size: 16),
              const Gap(10),
              Text(section.label).small(),
            ],
          ),
        ),
    ];
    return ColoredBox(
      color: Theme.of(context).colorScheme.muted.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: horizontal
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: buttons),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 8, 0, 8),
                    child: Text('SCENE'),
                  ).small().muted(),
                  ...buttons.take(2),
                  const Gap(24),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 0, 8),
                    child: Text('EDITOR'),
                  ).small().muted(),
                  ...buttons.skip(2),
                ],
              ),
      ),
    );
  }

  Widget _buildCanvasSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Reference resolution').semiBold(),
      const Gap(6),
      const Text(
        'Layout values in pixels use this size. Node positions remain proportional when you change it.',
      ).small().muted(),
      const Gap(16),
      StudioSelect<_CanvasPreset>(
        key: const ValueKey('canvas-resolution-preset'),
        value: _findPreset(),
        placeholder: const Text('Custom resolution'),
        onChanged: (preset) {
          setState(() {
            _fields['Canvas width']!.text = '${preset.width}';
            _fields['Canvas height']!.text = '${preset.height}';
          });
        },
        values: _CanvasPreset.values,
        formatValue: (preset) =>
            '${preset.label} · ${preset.width} × ${preset.height}',
      ),
      const Gap(16),
      StudioFieldRow(
        left: _buildField('Canvas width'),
        right: _buildField('Canvas height'),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlineButton(
          key: const ValueKey('swap-canvas-dimensions'),
          leading: const Icon(LucideIcons.arrowLeftRight, size: 14),
          onPressed: () => setState(() {
            final width = _fields['Canvas width']!.text;
            _fields['Canvas width']!.text = _fields['Canvas height']!.text;
            _fields['Canvas height']!.text = width;
          }),
          child: const Text('Swap dimensions').small(),
        ),
      ),
      const Gap(24),
      const Divider(),
      const Gap(20),
      StudioEnumSelect(
        label: 'Canvas fit',
        value: _fit,
        values: SceneCanvasFit.values,
        onChanged: (value) => setState(() => _fit = value),
      ),
      const Gap(8),
      Text(switch (_fit) {
        SceneCanvasFit.cover => 'Fill the display while preserving the reference aspect ratio. Edges may be cropped.',
        SceneCanvasFit.contain => 'Keep the entire scene visible. Extra space may appear around its edges.',
        SceneCanvasFit.reflow =>
          'Adapt the scene layout to the available display size.',
      }).small().muted(),
      const Gap(20),
      Switch(
        value: _safeArea,
        onChanged: (value) => setState(() => _safeArea = value),
        trailing: const Text('Respect safe area'),
      ),
      const Gap(8),
      const Text('Keep nodes inside the space available around display insets.')
          .small()
          .muted(),
    ],
  );

  Widget _buildBackgroundSection() {
    final asset = _fields['Background asset']!.text.trim();
    final color = _getBackgroundColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioEnumSelect(
          label: 'Background',
          value: _background,
          // Preserve a custom renderer already selected by the scene.
          values: {
            SceneBackgroundKind.solid,
            SceneBackgroundKind.image,
            widget.document.background.kind,
          },
          onChanged: (value) => setState(() => _background = value),
        ),
        const Gap(16),
        Container(
          height: 132,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: color ?? Theme.of(context).colorScheme.muted,
            border: Border.all(color: Theme.of(context).colorScheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _background == SceneBackgroundKind.image && asset.isNotEmpty
              ? Image(
                  image: ResizeImage.resizeIfNeeded(
                    960,
                    null,
                    widget.resolveAssetImage(asset),
                  ),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: const Text(
                      'Image unavailable. Check the asset path.',
                    ).small(),
                  ),
                )
              : Center(
                  child: Text(
                    _background == SceneBackgroundKind.solid
                        ? 'Solid color'
                        : 'Theme background',
                    style: TextStyle(
                      color: color != null && color.computeLuminance() < 0.4
                          ? Colors.white
                          : Colors.black,
                    ),
                  ).small(),
                ),
        ),
        const Gap(16),
        if (_background == SceneBackgroundKind.image) ...[
          if (widget.assetPaths.isNotEmpty) ...[
            StudioSelect<String>(
              key: const ValueKey('background-asset-select'),
              value: asset.isEmpty ? null : asset,
              placeholder: const Text('Choose a theme asset'),
              onChanged: (value) =>
                  setState(() => _fields['Background asset']!.text = value),
              values: {...widget.assetPaths, if (asset.isNotEmpty) asset},
              formatValue: (value) => value.split('/').last,
            ),
            const Gap(12),
          ],
          _buildField('Background asset'),
          const Text(
            'Use a registered theme asset, or import an image from the Assets tab.',
          ).small().muted(),
          const Gap(16),
        ],
        _buildField('Background color'),
        const Text('Hex color: #RRGGBB or #AARRGGBB.').small().muted(),
        const Gap(20),
        const Divider(),
        const Gap(20),
        StudioFieldRow(
          left: _buildField('Background blur'),
          right: _buildField('Scrim opacity'),
        ),
        const Text(
          'Blur softens the background. Scrim opacity adds a dark overlay from 0 (clear) to 1 (black).',
        ).small().muted(),
      ],
    );
  }

  Widget _buildAppearanceSection() {
    final brightness = switch (_themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final scheme = _palette.getColorScheme(brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioEnumSelect(
          label: 'Appearance',
          value: _themeMode,
          values: ThemeMode.values,
          formatValue: (mode) => switch (mode) {
            ThemeMode.system => 'Follow system',
            ThemeMode.light => 'Light',
            ThemeMode.dark => 'Dark',
          },
          onChanged: (value) => setState(() => _themeMode = value),
        ),
        const Gap(20),
        const Text('Color theme').semiBold(),
        const Gap(12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final palette in StudioPalette.values)
              Button(
                key: ValueKey('palette-${palette.name}'),
                style: palette == _palette
                    ? const ButtonStyle.secondary()
                    : const ButtonStyle.outline(),
                onPressed: () => setState(() => _palette = palette),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: palette.getColorScheme(Brightness.light).primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const Gap(8),
                    Text(palette.label).small(),
                    if (palette == _palette) ...[
                      const Gap(6),
                      const Icon(LucideIcons.check, size: 12),
                    ],
                  ],
                ),
              ),
          ],
        ),
        const Gap(24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.background,
            border: Border.all(color: scheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Editor preview',
                style: TextStyle(color: scheme.foreground),
              ).semiBold(),
              const Gap(6),
              Text(
                'Panels, controls, and selection colors',
                style: TextStyle(color: scheme.mutedForeground),
              ).small(),
              const Gap(20),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.secondary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Selected layer',
                        style: TextStyle(color: scheme.secondaryForeground),
                      ).small(),
                    ),
                  ),
                  const Gap(12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Save',
                      style: TextStyle(color: scheme.primaryForeground),
                    ).small(),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Gap(20),
        Align(
          alignment: Alignment.centerLeft,
          child: GhostButton(
            onPressed: () => setState(() {
              const defaults = StudioPreferences();
              _themeMode = defaults.themeMode;
              _palette = defaults.palette;
            }),
            child: const Text('Reset appearance'),
          ),
        ),
      ],
    );
  }

  Widget _buildGridSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Switch(
        value: _showGrid,
        onChanged: (value) => setState(() => _showGrid = value),
        trailing: const Text('Show grid'),
      ),
      const Gap(8),
      const Text('Overlay reference lines on the canvas while editing.')
          .small()
          .muted(),
      const Gap(24),
      Switch(
        value: _snapToGrid,
        onChanged: (value) => setState(() => _snapToGrid = value),
        trailing: const Text('Snap to grid'),
      ),
      const Gap(8),
      const Text(
        'Align moved nodes and resize handles to the grid. Snapping works even when grid lines are hidden.',
      ).small().muted(),
      const Gap(24),
      _buildField('Grid size (pixels)'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final size in [8, 16, 24, 32, 48, 64])
            Button(
              key: ValueKey('grid-preset-$size'),
              style: _fields['Grid size (pixels)']!.text == '$size'
                  ? const ButtonStyle.secondary()
                  : const ButtonStyle.outline(),
              onPressed: () =>
                  setState(() => _fields['Grid size (pixels)']!.text = '$size'),
              child: Text('$size').small(),
            ),
        ],
      ),
      const Gap(12),
      const Text(
        '4–512 reference pixels. Grid spacing follows the scene resolution, independently of zoom.',
      ).small().muted(),
      const Gap(24),
      const Divider(),
      const Gap(12),
      Align(
        alignment: Alignment.centerLeft,
        child: GhostButton(
          onPressed: () => setState(() {
            const defaults = StudioPreferences();
            _showGrid = defaults.showGrid;
            _snapToGrid = defaults.snapToGrid;
            _fields['Grid size (pixels)']!.text = '${defaults.gridSize}';
          }),
          child: const Text('Reset grid'),
        ),
      ),
    ],
  );

  Widget _buildField(String label) => StudioFormField(
    label: label,
    inputKey: ValueKey('setting-$label'),
    controller: _fields[label]!,
    onChanged: (_) => setState(() {}),
  );
}
