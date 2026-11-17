import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'studio_preferences.dart';
import 'studio_input.dart';
import 'studio_input_settings.dart';
import '../inspector/studio_form.dart';
import '../inspector/studio_form_values.dart';
import 'studio_theme.dart';
import '../canvas/studio_canvas_presets.dart';

class StudioSettings extends StatefulWidget {
  const StudioSettings({
    required this.document,
    required this.preferences,
    required this.assetPaths,
    required this.resolveAssetImage,
    required this.supportsImageBackground,
    required this.onApply,
    super.key,
  });

  final SceneDocument document;
  final StudioPreferences preferences;
  final List<String> assetPaths;
  final ImageProvider Function(String) resolveAssetImage;
  final bool supportsImageBackground;
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
  ),
  input(
    'Shortcuts',
    LucideIcons.keyboard,
    'Shortcuts, bindings, and navigation gestures',
  );

  const _SettingsSection(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;

  bool get isSceneSetting => this == canvas || this == background;
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
  late StudioInputBindings _input;
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
    _input = preferences.input;
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
    return widget.document.background.copyWith(
      kind: _background,
      asset: asset.isEmpty ? null : asset,
      color: decodeSceneColor(_fields['Background color']!.text.trim()),
      blurSigma: _getNumber('Background blur'),
      scrimOpacity: _getNumber('Scrim opacity'),
      shader: _background == SceneBackgroundKind.custom
          ? widget.document.background.shader
          : null,
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
      input: _input,
    );
  }

  void _apply() {
    // Parsing errors belong to the category being read. Codec errors returned
    // by the editor name canvas/background; bring that category into view too.
    _SettingsSection? currentStep;
    try {
      currentStep = _SettingsSection.canvas;
      final canvas = _getCanvas();
      currentStep = _SettingsSection.background;
      final background = _getBackground();
      currentStep = _SettingsSection.grid;
      final preferences = _getPreferences();
      currentStep = null;
      widget.onApply(canvas, background, preferences);
      Navigator.of(context).pop();
    } on FormatException catch (error) {
      final message = error.message.toLowerCase();
      final targetSection =
          currentStep ??
          (message.contains('background')
              ? _SettingsSection.background
              : message.contains('canvas')
              ? _SettingsSection.canvas
              : _section);
      setState(() {
        _section = targetSection;
        _error = error.message;
        _errorSection = _section;
      });
    }
  }

  StudioCanvasPreset? _findPreset() {
    final width = int.tryParse(_fields['Canvas width']!.text);
    final height = int.tryParse(_fields['Canvas height']!.text);
    return StudioCanvasPreset.values
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

  void _swapCanvasDimensions() {
    final width = _fields['Canvas width']!.text;
    _fields['Canvas width']!.text = _fields['Canvas height']!.text;
    _fields['Canvas height']!.text = width;
  }

  void _resetAppearance() => setState(() {
    const defaults = StudioPreferences();
    _themeMode = defaults.themeMode;
    _palette = defaults.palette;
  });

  void _resetGrid() => setState(() {
    const defaults = StudioPreferences();
    _showGrid = defaults.showGrid;
    _snapToGrid = defaults.snapToGrid;
    _fields['Grid size (pixels)']!.text = '${defaults.gridSize}';
  });

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _buildSectionContent() => switch (_section) {
    _SettingsSection.canvas => _CanvasSettingsSection(
      widthController: _fields['Canvas width']!,
      heightController: _fields['Canvas height']!,
      findPreset: _findPreset,
      fit: _fit,
      safeArea: _safeArea,
      onSelectPreset: (preset) {
        _fields['Canvas width']!.text = '${preset.width}';
        _fields['Canvas height']!.text = '${preset.height}';
      },
      onSwapDimensions: _swapCanvasDimensions,
      onFitChanged: (value) => setState(() => _fit = value),
      onSafeAreaChanged: (value) => setState(() => _safeArea = value),
    ),
    _SettingsSection.background => _BackgroundSettingsSection(
      backgroundKind: _background,
      availableKinds: {
        SceneBackgroundKind.solid,
        if (widget.supportsImageBackground) SceneBackgroundKind.image,
        widget.document.background.kind,
      },
      shader: widget.document.background.shader,
      assetPaths: widget.assetPaths,
      assetController: _fields['Background asset']!,
      colorController: _fields['Background color']!,
      blurController: _fields['Background blur']!,
      scrimController: _fields['Scrim opacity']!,
      resolveAssetImage: widget.resolveAssetImage,
      getBackgroundColor: _getBackgroundColor,
      onBackgroundChanged: (value) => setState(() => _background = value),
    ),
    _SettingsSection.appearance => _AppearanceSettingsSection(
      themeMode: _themeMode,
      palette: _palette,
      onThemeModeChanged: (value) => setState(() => _themeMode = value),
      onPaletteChanged: (value) => setState(() => _palette = value),
      onReset: _resetAppearance,
    ),
    _SettingsSection.grid => _GridSettingsSection(
      showGrid: _showGrid,
      snapToGrid: _snapToGrid,
      gridSizeController: _fields['Grid size (pixels)']!,
      onShowGridChanged: (value) => setState(() => _showGrid = value),
      onSnapToGridChanged: (value) => setState(() => _snapToGrid = value),
      onReset: _resetGrid,
    ),
    _SettingsSection.input => StudioInputSettings(
      value: _input,
      onChanged: (value) => setState(() => _input = value),
    ),
  };

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
              const _SettingsHeader(),
              const Divider(),
              if (compact)
                _SettingsNavigation(
                  horizontal: true,
                  selected: _section,
                  onSelect: (section) => setState(() => _section = section),
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!compact) ...[
                      SizedBox(
                        width: 184,
                        child: _SettingsNavigation(
                          horizontal: false,
                          selected: _section,
                          onSelect: (section) =>
                              setState(() => _section = section),
                        ),
                      ),
                      const VerticalDivider(),
                    ],
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
                              _SettingsErrorBanner(error: _error!),
                              const Gap(16),
                            ],
                            _buildSectionContent(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              _SettingsFooter(
                compact: compact,
                isSceneSetting: _section.isSceneSetting,
                onCancel: () => Navigator.of(context).pop(),
                onApply: _apply,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
    child: Row(
      children: [
        const Icon(LucideIcons.settings2, size: 20),
        const Gap(12),
        const Text('Studio settings').large().semiBold(),
      ],
    ),
  );
}

class _SettingsErrorBanner extends StatelessWidget {
  const _SettingsErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.destructive.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: StudioFormError(error),
    );
  }
}

class _SettingsFooter extends StatelessWidget {
  const _SettingsFooter({
    required this.compact,
    required this.isSceneSetting,
    required this.onCancel,
    required this.onApply,
  });

  final bool compact;
  final bool isSceneSetting;
  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    child: Row(
      children: [
        if (!compact) ...[
          Expanded(
            child: Text(
              isSceneSetting
                  ? 'Scene changes can be undone.\nSave scene to write them to disk.'
                  : 'Editor preferences are saved when applied.\nYour theme appearance stays the same.',
            ).small().muted(),
          ),
          const Gap(16),
        ] else
          const Spacer(),
        OutlineButton(onPressed: onCancel, child: const Text('Cancel')),
        const Gap(8),
        PrimaryButton(onPressed: onApply, child: const Text('Apply settings')),
      ],
    ),
  );
}

class _SettingsNavigation extends StatelessWidget {
  const _SettingsNavigation({
    required this.horizontal,
    required this.selected,
    required this.onSelect,
  });

  final bool horizontal;
  final _SettingsSection selected;
  final ValueChanged<_SettingsSection> onSelect;

  Widget _buildItem(_SettingsSection section) => Button(
    key: ValueKey('settings-nav-${section.name}'),
    style: selected == section
        ? const ButtonStyle.secondary()
        : const ButtonStyle.ghost(),
    onPressed: () => onSelect(section),
    child: Row(
      mainAxisSize: horizontal ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Icon(section.icon, size: 16),
        const Gap(10),
        Text(section.label).small(),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.muted.withValues(alpha: 0.25),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: horizontal
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _SettingsSection.values.map(_buildItem).toList(),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 0, 8),
                  child: Text('SCENE'),
                ).small().muted(),
                for (final section in _SettingsSection.values.where(
                  (s) => s.isSceneSetting,
                ))
                  _buildItem(section),
                const Gap(24),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 0, 8),
                  child: Text('EDITOR'),
                ).small().muted(),
                for (final section in _SettingsSection.values.where(
                  (s) => !s.isSceneSetting,
                ))
                  _buildItem(section),
              ],
            ),
    ),
  );
}

class _SettingsTextField extends StatelessWidget {
  const _SettingsTextField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => StudioFormField(
    label: label,
    inputKey: ValueKey('setting-$label'),
    controller: controller,
  );
}

class _CanvasSettingsSection extends StatelessWidget {
  const _CanvasSettingsSection({
    required this.widthController,
    required this.heightController,
    required this.findPreset,
    required this.fit,
    required this.safeArea,
    required this.onSelectPreset,
    required this.onSwapDimensions,
    required this.onFitChanged,
    required this.onSafeAreaChanged,
  });

  final TextEditingController widthController;
  final TextEditingController heightController;
  final StudioCanvasPreset? Function() findPreset;
  final SceneCanvasFit fit;
  final bool safeArea;
  final ValueChanged<StudioCanvasPreset> onSelectPreset;
  final VoidCallback onSwapDimensions;
  final ValueChanged<SceneCanvasFit> onFitChanged;
  final ValueChanged<bool> onSafeAreaChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Reference resolution').semiBold(),
      const Gap(6),
      const Text(
        'Layout values in pixels use this size. Node positions remain proportional when you change it.',
      ).small().muted(),
      const Gap(16),
      ListenableBuilder(
        listenable: Listenable.merge([widthController, heightController]),
        builder: (context, _) => StudioSelect<StudioCanvasPreset>(
          key: const ValueKey('canvas-resolution-preset'),
          value: findPreset(),
          placeholder: const Text('Custom resolution'),
          onChanged: onSelectPreset,
          values: StudioCanvasPreset.values,
          formatValue: (preset) =>
              '${preset.label} · ${preset.width} × ${preset.height}',
        ),
      ),
      const Gap(16),
      StudioFieldRow(
        left: _SettingsTextField(
          label: 'Canvas width',
          controller: widthController,
        ),
        right: _SettingsTextField(
          label: 'Canvas height',
          controller: heightController,
        ),
      ),
      const Gap(10),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlineButton(
          key: const ValueKey('swap-canvas-dimensions'),
          leading: const Icon(LucideIcons.arrowLeftRight, size: 14),
          onPressed: onSwapDimensions,
          child: const Text('Swap dimensions').small(),
        ),
      ),
      const Gap(24),
      const Divider(),
      const Gap(20),
      StudioEnumSelect(
        label: 'Canvas fit',
        value: fit,
        values: SceneCanvasFit.values,
        onChanged: onFitChanged,
      ),
      const Gap(8),
      Text(switch (fit) {
        SceneCanvasFit.cover => 'Fill the display while preserving the reference aspect ratio. Edges may be cropped.',
        SceneCanvasFit.contain => 'Keep the entire scene visible. Extra space may appear around its edges.',
        SceneCanvasFit.reflow =>
          'Adapt the scene layout to the available display size.',
      }).small().muted(),
      const Gap(20),
      Switch(
        value: safeArea,
        onChanged: onSafeAreaChanged,
        trailing: const Text('Respect safe area'),
      ),
      const Gap(8),
      const Text('Keep nodes inside the space available around display insets.')
          .small()
          .muted(),
    ],
  );
}

class _BackgroundSettingsSection extends StatelessWidget {
  const _BackgroundSettingsSection({
    required this.backgroundKind,
    required this.availableKinds,
    required this.shader,
    required this.assetPaths,
    required this.assetController,
    required this.colorController,
    required this.blurController,
    required this.scrimController,
    required this.resolveAssetImage,
    required this.getBackgroundColor,
    required this.onBackgroundChanged,
  });

  final SceneBackgroundKind backgroundKind;
  final Iterable<SceneBackgroundKind> availableKinds;
  final SceneShader? shader;
  final List<String> assetPaths;
  final TextEditingController assetController;
  final TextEditingController colorController;
  final TextEditingController blurController;
  final TextEditingController scrimController;
  final ImageProvider Function(String) resolveAssetImage;
  final Color? Function() getBackgroundColor;
  final ValueChanged<SceneBackgroundKind> onBackgroundChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StudioEnumSelect(
        label: 'Background',
        value: backgroundKind,
        // Preserve a custom renderer already selected by the scene.
        values: availableKinds,
        onChanged: onBackgroundChanged,
      ),
      const Gap(16),
      ListenableBuilder(
        listenable: Listenable.merge([colorController, assetController]),
        builder: (context, _) {
          final asset = assetController.text.trim();
          final color = getBackgroundColor();
          return Container(
            height: 132,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: color ?? Theme.of(context).colorScheme.muted,
              border: Border.all(color: Theme.of(context).colorScheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                backgroundKind == SceneBackgroundKind.image && asset.isNotEmpty
                ? Image(
                    image: ResizeImage.resizeIfNeeded(
                      960,
                      null,
                      resolveAssetImage(asset),
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
                      backgroundKind == SceneBackgroundKind.solid
                          ? 'Solid color'
                          : backgroundKind == SceneBackgroundKind.custom &&
                                shader != null
                          ? 'Custom shader: ${shader!.asset.split('/').last}'
                          : 'Theme background',
                      style: TextStyle(
                        color: color != null && color.computeLuminance() < 0.4
                            ? Colors.white
                            : Colors.black,
                      ),
                    ).small(),
                  ),
          );
        },
      ),
      const Gap(16),
      if (backgroundKind == SceneBackgroundKind.custom && shader != null) ...[
        Text('Shader: ${shader!.asset}').small().muted(),
        const Gap(16),
      ],
      if (backgroundKind == SceneBackgroundKind.image) ...[
        if (assetPaths.isNotEmpty) ...[
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: assetController,
            builder: (context, value, _) {
              final asset = value.text.trim();
              return StudioSelect<String>(
                key: const ValueKey('background-asset-select'),
                value: asset.isEmpty ? null : asset,
                placeholder: const Text('Choose a theme asset'),
                onChanged: (selected) => assetController.text = selected,
                values: {...assetPaths, if (asset.isNotEmpty) asset},
                formatValue: (path) => path.split('/').last,
              );
            },
          ),
          const Gap(12),
        ],
        _SettingsTextField(
          label: 'Background asset',
          controller: assetController,
        ),
        const Gap(6),
        const Text(
          'Use a registered theme asset, or import an image from the Assets tab.',
        ).small().muted(),
        const Gap(16),
      ],
      _SettingsTextField(
        label: 'Background color',
        controller: colorController,
      ),
      const Gap(6),
      const Text('Hex color: #RRGGBB or #AARRGGBB.').small().muted(),
      const Gap(20),
      const Divider(),
      const Gap(20),
      StudioFieldRow(
        left: _SettingsTextField(
          label: 'Background blur',
          controller: blurController,
        ),
        right: _SettingsTextField(
          label: 'Scrim opacity',
          controller: scrimController,
        ),
      ),
      const Gap(8),
      const Text(
        'Blur softens the background. Scrim opacity adds a dark overlay from 0 (clear) to 1 (black).',
      ).small().muted(),
    ],
  );
}

class _AppearanceSettingsSection extends StatelessWidget {
  const _AppearanceSettingsSection({
    required this.themeMode,
    required this.palette,
    required this.onThemeModeChanged,
    required this.onPaletteChanged,
    required this.onReset,
  });

  final ThemeMode themeMode;
  final StudioPalette palette;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<StudioPalette> onPaletteChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final brightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final scheme = palette.getColorScheme(brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioEnumSelect(
          label: 'Appearance',
          value: themeMode,
          values: ThemeMode.values,
          formatValue: (mode) => switch (mode) {
            ThemeMode.system => 'Follow system',
            ThemeMode.light => 'Light',
            ThemeMode.dark => 'Dark',
          },
          onChanged: onThemeModeChanged,
        ),
        const Gap(20),
        const Text('Color theme').semiBold(),
        const Gap(12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final candidate in StudioPalette.values)
              Button(
                key: ValueKey('palette-${candidate.name}'),
                style: candidate == palette
                    ? const ButtonStyle.secondary()
                    : const ButtonStyle.outline(),
                onPressed: () => onPaletteChanged(candidate),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: candidate
                            .getColorScheme(Brightness.light)
                            .primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const Gap(8),
                    Text(candidate.label).small(),
                    if (candidate == palette) ...[
                      const Gap(6),
                      const Icon(LucideIcons.check, size: 12),
                    ],
                  ],
                ),
              ),
          ],
        ),
        const Gap(24),
        _AppearancePreviewCard(scheme: scheme),
        const Gap(20),
        Align(
          alignment: Alignment.centerLeft,
          child: GhostButton(
            onPressed: onReset,
            child: const Text('Reset appearance'),
          ),
        ),
      ],
    );
  }
}

class _AppearancePreviewCard extends StatelessWidget {
  const _AppearancePreviewCard({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Container(
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
  );
}

class _GridSettingsSection extends StatelessWidget {
  const _GridSettingsSection({
    required this.showGrid,
    required this.snapToGrid,
    required this.gridSizeController,
    required this.onShowGridChanged,
    required this.onSnapToGridChanged,
    required this.onReset,
  });

  final bool showGrid;
  final bool snapToGrid;
  final TextEditingController gridSizeController;
  final ValueChanged<bool> onShowGridChanged;
  final ValueChanged<bool> onSnapToGridChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Switch(
        value: showGrid,
        onChanged: onShowGridChanged,
        trailing: const Text('Show grid'),
      ),
      const Gap(8),
      const Text('Overlay reference lines on the canvas while editing.')
          .small()
          .muted(),
      const Gap(24),
      Switch(
        value: snapToGrid,
        onChanged: onSnapToGridChanged,
        trailing: const Text('Snap to grid'),
      ),
      const Gap(8),
      const Text(
        'Align moved nodes and resize handles to the grid. Snapping works even when grid lines are hidden.',
      ).small().muted(),
      const Gap(24),
      _SettingsTextField(
        label: 'Grid size (pixels)',
        controller: gridSizeController,
      ),
      const Gap(10),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: gridSizeController,
        builder: (context, value, _) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final size in [8, 16, 24, 32, 48, 64])
              Button(
                key: ValueKey('grid-preset-$size'),
                style: value.text == '$size'
                    ? const ButtonStyle.secondary()
                    : const ButtonStyle.outline(),
                onPressed: () => gridSizeController.text = '$size',
                child: Text('$size').small(),
              ),
          ],
        ),
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
        child: GhostButton(onPressed: onReset, child: const Text('Reset grid')),
      ),
    ],
  );
}
