import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'studio_preferences.dart';
import 'studio_form.dart';

class StudioSettings extends StatefulWidget {
  const StudioSettings({
    required this.document,
    required this.preferences,
    required this.onApply,
    super.key,
  });

  final SceneDocument document;
  final StudioPreferences preferences;
  final void Function(SceneCanvas, SceneBackground, StudioPreferences) onApply;

  @override
  State<StudioSettings> createState() => _StudioSettingsState();
}

enum _SettingsSection { canvas, background, preferences }

class _StudioSettingsState extends State<StudioSettings> {
  final _fields = <String, TextEditingController>{};
  late SceneCanvasFit _fit;
  late SceneBackgroundKind _background;
  late bool _safeArea;
  late bool _darkMode;
  late bool _showGrid;
  late bool _snapToGrid;
  String? _error;

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
    _darkMode = preferences.darkMode;
    _showGrid = preferences.showGrid;
    _snapToGrid = preferences.snapToGrid;
  }

  int _getInteger(String field) {
    final value = int.tryParse(_fields[field]!.text);
    if (value == null) throw FormatException('$field must be an integer.');
    return value;
  }

  double _getNumber(String field) {
    final value = double.tryParse(_fields[field]!.text);
    if (value == null || !value.isFinite) {
      throw FormatException('$field must be a finite number.');
    }
    return value;
  }

  void _apply() {
    try {
      final gridSize = _getInteger('Grid size (pixels)');
      StudioPreferences.validateGridSize(gridSize);
      final asset = _fields['Background asset']!.text.trim();
      if (_background == SceneBackgroundKind.image && asset.isEmpty) {
        throw const FormatException(
          'Choose or import a background image first.',
        );
      }
      widget.onApply(
        widget.document.canvas.copyWith(
          referenceWidth: _getInteger('Canvas width'),
          referenceHeight: _getInteger('Canvas height'),
          fit: _fit,
          useSafeArea: _safeArea,
        ),
        SceneBackground(
          kind: _background,
          asset: asset.isEmpty ? null : asset,
          color: decodeSceneColor(_fields['Background color']!.text.trim()),
          blurSigma: _getNumber('Background blur'),
          scrimOpacity: _getNumber('Scrim opacity'),
          rendererId: widget.document.background.rendererId,
        ),
        StudioPreferences(
          darkMode: _darkMode,
          showGrid: _showGrid,
          snapToGrid: _snapToGrid,
          gridSize: gridSize,
        ),
      );
      Navigator.of(context).pop();
    } on FormatException catch (error) {
      setState(() => _error = error.message);
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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Studio settings'),
    content: SizedBox(
      width: 480,
      height: 480,
      child: ListView.separated(
        key: const ValueKey('settings-list'),
        itemCount: _SettingsSection.values.length,
        separatorBuilder: (context, index) => Gap(index == 0 ? 20 : 8),
        itemBuilder: (context, index) =>
            switch (_SettingsSection.values[index]) {
              _SettingsSection.canvas => _buildCanvasSection(),
              _SettingsSection.background => _buildBackgroundSection(),
              _SettingsSection.preferences => _buildPreferencesSection(),
            },
      ),
    ),
    actions: [
      if (_error case final error?)
        SizedBox(width: 260, child: StudioFormError(error)),
      OutlineButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      PrimaryButton(onPressed: _apply, child: const Text('Apply settings')),
    ],
  );

  Widget _buildCanvasSection() => StudioFormSection(
    title: 'Canvas',
    children: [
      StudioFieldRow(
        left: _buildField('Canvas width'),
        right: _buildField('Canvas height'),
      ),
      StudioEnumSelect(
        label: 'Canvas fit',
        value: _fit,
        values: SceneCanvasFit.values,
        onChanged: (value) => setState(() => _fit = value),
      ),
      const Gap(12),
      Switch(
        value: _safeArea,
        onChanged: (value) => setState(() => _safeArea = value),
        trailing: const Text('Respect safe area'),
      ),
    ],
  );

  Widget _buildBackgroundSection() => StudioFormSection(
    title: 'Background',
    children: [
      StudioEnumSelect(
        label: 'Background',
        value: _background,
        // Preserve custom compiled renderers already used by the document.
        values: {
          SceneBackgroundKind.solid,
          SceneBackgroundKind.image,
          widget.document.background.kind,
        },
        onChanged: (value) => setState(() => _background = value),
      ),
      const Gap(12),
      _buildField('Background color'),
      _buildField('Background asset'),
      StudioFieldRow(
        left: _buildField('Background blur'),
        right: _buildField('Scrim opacity'),
      ),
    ],
  );

  Widget _buildPreferencesSection() => StudioFormSection(
    title: 'Editor preferences',
    children: [
      Switch(
        value: _darkMode,
        onChanged: (value) => setState(() => _darkMode = value),
        trailing: const Text('Dark appearance'),
      ),
      const Gap(12),
      Switch(
        value: _showGrid,
        onChanged: (value) => setState(() => _showGrid = value),
        trailing: const Text('Show grid'),
      ),
      const Gap(12),
      Switch(
        value: _snapToGrid,
        onChanged: (value) => setState(() => _snapToGrid = value),
        trailing: const Text('Snap to grid'),
      ),
      const Gap(12),
      _buildField('Grid size (pixels)'),
      const Text(
        'Scene settings use Undo and Save scene. Editor preferences are saved automatically.',
      ).small().muted(),
    ],
  );

  Widget _buildField(String label) => StudioFormField(
    label: label,
    inputKey: ValueKey('setting-$label'),
    controller: _fields[label]!,
  );
}
