import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../model/studio_canvas_presets.dart';
import '../model/studio_theme.dart';
import '../ui/studio_form.dart';

enum StudioSettingsSection {
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

  const StudioSettingsSection(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;

  bool get isSceneSetting => this == canvas || this == background;
}

class StudioSettingsHeader extends StatelessWidget {
  const StudioSettingsHeader({super.key});

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

class StudioSettingsErrorBanner extends StatelessWidget {
  const StudioSettingsErrorBanner({required this.error, super.key});

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

class StudioSettingsFooter extends StatelessWidget {
  const StudioSettingsFooter({
    required this.compact,
    required this.isSceneSetting,
    required this.onCancel,
    required this.onApply,
    super.key,
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

class StudioSettingsNavigation extends StatelessWidget {
  const StudioSettingsNavigation({
    required this.horizontal,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final bool horizontal;
  final StudioSettingsSection selected;
  final ValueChanged<StudioSettingsSection> onSelect;

  Widget _buildItem(StudioSettingsSection section) => Button(
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
                children: StudioSettingsSection.values.map(_buildItem).toList(),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 0, 8),
                  child: Text('SCENE'),
                ).small().muted(),
                for (final section in StudioSettingsSection.values.where(
                  (s) => s.isSceneSetting,
                ))
                  _buildItem(section),
                const Gap(24),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 0, 8),
                  child: Text('EDITOR'),
                ).small().muted(),
                for (final section in StudioSettingsSection.values.where(
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

class CanvasSettingsSection extends StatelessWidget {
  const CanvasSettingsSection({
    required this.widthController,
    required this.heightController,
    required this.findPreset,
    required this.fit,
    required this.safeArea,
    required this.onSelectPreset,
    required this.onSwapDimensions,
    required this.onFitChanged,
    required this.onSafeAreaChanged,
    super.key,
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

class BackgroundSettingsSection extends StatelessWidget {
  const BackgroundSettingsSection({
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
    super.key,
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
  Widget build(BuildContext context) {
    final customShader = backgroundKind == SceneBackgroundKind.custom
        ? shader
        : null;
    return Column(
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
                  backgroundKind == SceneBackgroundKind.image &&
                      asset.isNotEmpty
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
                            : customShader != null
                            ? 'Custom shader: ${customShader.asset.split('/').last}'
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
        if (customShader != null) ...[
          Text('Shader: ${customShader.asset}').small().muted(),
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
}

class AppearanceSettingsSection extends StatelessWidget {
  const AppearanceSettingsSection({
    required this.themeMode,
    required this.palette,
    required this.onThemeModeChanged,
    required this.onPaletteChanged,
    required this.onReset,
    super.key,
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

class GridSettingsSection extends StatelessWidget {
  const GridSettingsSection({
    required this.showGrid,
    required this.snapToGrid,
    required this.gridSizeController,
    required this.onShowGridChanged,
    required this.onSnapToGridChanged,
    required this.onReset,
    super.key,
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
