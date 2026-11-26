import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../model/studio_canvas_presets.dart';
import '../model/studio_input.dart';
import '../model/studio_preferences.dart';
import '../model/studio_theme.dart';
import '../ui/studio_form_values.dart';
import 'studio_input_settings.dart';
import 'studio_settings_sections.dart';

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

/// Drafts live for the dialog, independently of the selected category. Apply
/// hands the complete draft to the scene editor so validation and undo keep
/// using the same document boundary as canvas and inspector edits.
class _StudioSettingsState extends State<StudioSettings> {
  late final TextEditingController _canvasWidthController;
  late final TextEditingController _canvasHeightController;
  late final TextEditingController _backgroundColorController;
  late final TextEditingController _backgroundAssetController;
  late final TextEditingController _backgroundBlurController;
  late final TextEditingController _scrimOpacityController;
  late final TextEditingController _gridSizeController;
  StudioSettingsSection _section = StudioSettingsSection.canvas;
  late SceneCanvasFit _fit;
  late SceneBackgroundKind _background;
  late bool _safeArea;
  late ThemeMode _themeMode;
  late StudioPalette _palette;
  late bool _showGrid;
  late bool _snapToGrid;
  late StudioInputBindings _input;
  String? _error;
  StudioSettingsSection? _errorSection;

  @override
  void initState() {
    super.initState();
    final scene = widget.document;
    final preferences = widget.preferences;
    _canvasWidthController = TextEditingController(
      text: '${scene.canvas.referenceWidth}',
    );
    _canvasHeightController = TextEditingController(
      text: '${scene.canvas.referenceHeight}',
    );
    _backgroundColorController = TextEditingController(
      text: encodeSceneColor(scene.background.color),
    );
    _backgroundAssetController = TextEditingController(
      text: scene.background.asset ?? '',
    );
    _backgroundBlurController = TextEditingController(
      text: '${scene.background.blurSigma}',
    );
    _scrimOpacityController = TextEditingController(
      text: '${scene.background.scrimOpacity}',
    );
    _gridSizeController = TextEditingController(
      text: '${preferences.gridSize}',
    );
    _fit = scene.canvas.fit;
    _safeArea = scene.canvas.useSafeArea;
    _background = scene.background.kind;
    _themeMode = preferences.themeMode;
    _palette = preferences.palette;
    _showGrid = preferences.showGrid;
    _snapToGrid = preferences.snapToGrid;
    _input = preferences.input;
  }

  SceneCanvas _getCanvas() => widget.document.canvas.copyWith(
    referenceWidth: getIntegerInput(
      'Canvas width',
      _canvasWidthController.text,
    ),
    referenceHeight: getIntegerInput(
      'Canvas height',
      _canvasHeightController.text,
    ),
    fit: _fit,
    useSafeArea: _safeArea,
  );

  SceneBackground _getBackground() {
    final asset = _backgroundAssetController.text.trim();
    if (_background == SceneBackgroundKind.image && asset.isEmpty) {
      throw const FormatException('Choose or import a background image first.');
    }
    return widget.document.background.copyWith(
      kind: _background,
      asset: asset.isEmpty ? null : asset,
      color: decodeSceneColor(_backgroundColorController.text.trim()),
      blurSigma: getFiniteNumberInput(
        'Background blur',
        _backgroundBlurController.text,
      ),
      scrimOpacity: getFiniteNumberInput(
        'Scrim opacity',
        _scrimOpacityController.text,
      ),
      shader: _background == SceneBackgroundKind.custom
          ? widget.document.background.shader
          : null,
    );
  }

  StudioPreferences _getPreferences() {
    final gridSize = getIntegerInput(
      'Grid size (pixels)',
      _gridSizeController.text,
    );
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
    StudioSettingsSection? currentStep;
    try {
      currentStep = StudioSettingsSection.canvas;
      final canvas = _getCanvas();
      currentStep = StudioSettingsSection.background;
      final background = _getBackground();
      currentStep = StudioSettingsSection.grid;
      final preferences = _getPreferences();
      currentStep = null;
      widget.onApply(canvas, background, preferences);
      Navigator.of(context).pop();
    } on FormatException catch (error) {
      final message = error.message.toLowerCase();
      final targetSection =
          currentStep ??
          (message.contains('background')
              ? StudioSettingsSection.background
              : message.contains('canvas')
              ? StudioSettingsSection.canvas
              : _section);
      setState(() {
        _section = targetSection;
        _error = error.message;
        _errorSection = _section;
      });
    }
  }

  StudioCanvasPreset? _findPreset() {
    final width = int.tryParse(_canvasWidthController.text);
    final height = int.tryParse(_canvasHeightController.text);
    return StudioCanvasPreset.values
        .where((preset) => preset.width == width && preset.height == height)
        .firstOrNull;
  }

  Color? _getBackgroundColor() {
    try {
      return Color(decodeSceneColor(_backgroundColorController.text.trim()));
    } on FormatException {
      return null;
    }
  }

  void _swapCanvasDimensions() {
    final width = _canvasWidthController.text;
    _canvasWidthController.text = _canvasHeightController.text;
    _canvasHeightController.text = width;
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
    _gridSizeController.text = '${defaults.gridSize}';
  });

  @override
  void dispose() {
    _canvasWidthController.dispose();
    _canvasHeightController.dispose();
    _backgroundColorController.dispose();
    _backgroundAssetController.dispose();
    _backgroundBlurController.dispose();
    _scrimOpacityController.dispose();
    _gridSizeController.dispose();
    super.dispose();
  }

  Widget _buildSectionContent() => switch (_section) {
    StudioSettingsSection.canvas => CanvasSettingsSection(
      widthController: _canvasWidthController,
      heightController: _canvasHeightController,
      findPreset: _findPreset,
      fit: _fit,
      safeArea: _safeArea,
      onSelectPreset: (preset) {
        _canvasWidthController.text = '${preset.width}';
        _canvasHeightController.text = '${preset.height}';
      },
      onSwapDimensions: _swapCanvasDimensions,
      onFitChanged: (value) => setState(() => _fit = value),
      onSafeAreaChanged: (value) => setState(() => _safeArea = value),
    ),
    StudioSettingsSection.background => BackgroundSettingsSection(
      backgroundKind: _background,
      availableKinds: {
        SceneBackgroundKind.solid,
        if (widget.supportsImageBackground) SceneBackgroundKind.image,
        widget.document.background.kind,
      },
      shader: widget.document.background.shader,
      assetPaths: widget.assetPaths,
      assetController: _backgroundAssetController,
      colorController: _backgroundColorController,
      blurController: _backgroundBlurController,
      scrimController: _scrimOpacityController,
      resolveAssetImage: widget.resolveAssetImage,
      getBackgroundColor: _getBackgroundColor,
      onBackgroundChanged: (value) => setState(() => _background = value),
    ),
    StudioSettingsSection.appearance => AppearanceSettingsSection(
      themeMode: _themeMode,
      palette: _palette,
      onThemeModeChanged: (value) => setState(() => _themeMode = value),
      onPaletteChanged: (value) => setState(() => _palette = value),
      onReset: _resetAppearance,
    ),
    StudioSettingsSection.grid => GridSettingsSection(
      showGrid: _showGrid,
      snapToGrid: _snapToGrid,
      gridSizeController: _gridSizeController,
      onShowGridChanged: (value) => setState(() => _showGrid = value),
      onSnapToGridChanged: (value) => setState(() => _snapToGrid = value),
      onReset: _resetGrid,
    ),
    StudioSettingsSection.input => StudioInputSettings(
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
    final error = _errorSection == _section ? _error : null;
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
              const StudioSettingsHeader(),
              const Divider(),
              if (compact)
                StudioSettingsNavigation(
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
                        child: StudioSettingsNavigation(
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
                            if (error != null) ...[
                              StudioSettingsErrorBanner(error: error),
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
              StudioSettingsFooter(
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
