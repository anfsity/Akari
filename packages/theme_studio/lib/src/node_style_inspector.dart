import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_form.dart';

class NodeStyleInspector extends StatefulWidget {
  const NodeStyleInspector({required this.editor, super.key});
  final SceneEditor editor;
  @override
  State<NodeStyleInspector> createState() => _NodeStyleInspectorState();
}

class _NodeStyleInspectorState extends State<NodeStyleInspector> {
  late SceneStyle _draft;
  @override
  void initState() {
    super.initState();
    _updateDraft();
  }

  @override
  void didUpdateWidget(NodeStyleInspector old) {
    super.didUpdateWidget(old);
    _updateDraft();
  }

  void _updateDraft() {
    _draft =
        widget.editor.document.styleTokens[widget
            .editor
            .selectedNode
            .styleToken] ??
        const SceneStyle();
  }

  void _commit(SceneStyle style) {
    widget.editor.updateSelectionStyle(style);
  }

  void _preview(SceneStyle style) {
    setState(() => _draft = style);
    widget.editor.previewSelectionStyle(style);
  }

  Widget _color(String label, int value, SceneStyle Function(int) update) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(child: Text(label).small().muted()),
            ColorInput(
              key: ValueKey('style-$label'),
              value: ColorDerivative.fromColor(Color(value)),
              theme: const ColorInputTheme(showAlpha: true),
              onChanging: (value) =>
                  _preview(update(value.toColor().toARGB32())),
              onChanged: (value) => _commit(update(value.toColor().toARGB32())),
            ),
          ],
        ),
      );

  Widget _slider(
    String label,
    double value,
    double maximum,
    SceneStyle Function(double) update, {
    double minimum = 0,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label  ${value.toStringAsFixed(1)}').small().muted(),
        const Gap(6),
        StudioPreviewSlider(
          key: ValueKey('style-$label'),
          value: value,
          maximum: maximum,
          minimum: minimum,
          onCancel: () {
            widget.editor.cancelPreview();
            setState(_updateDraft);
          },
          onPreview: (value) => _preview(update(value)),
          onCommit: (value) => _commit(update(value)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => StudioFormSection(
    title: 'Visual style',
    children: [
      StudioSelect<String>(
        key: const ValueKey('style-token'),
        value: widget.editor.selectedNode.styleToken,
        values: widget.editor.document.styleTokens.keys,
        formatValue: (token) => token,
        placeholder: const Text('New style token on first edit'),
        onChanged: widget.editor.updateSelectionStyleToken,
      ),
      const Gap(8),
      if (widget.editor.selectedNode.styleToken != null) ...[
        const Text('Editing a shared token updates every layer that uses it.')
            .small()
            .muted(),
        GhostButton(
          onPressed: () => widget.editor.updateSelectionStyleToken(null),
          child: const Text('Detach style'),
        ),
      ],
      const Gap(8),
      _color('Fill', _draft.fill, (value) => _draft.copyWith(fill: value)),
      Row(
        children: [
          const Expanded(child: Text('Gradient')),
          Switch(
            value: _draft.gradientEnd != null,
            onChanged: (enabled) => _commit(
              _draft.copyWith(gradientEnd: enabled ? 0xff6366f1 : null),
            ),
          ),
        ],
      ),
      const Gap(12),
      if (_draft.gradientEnd != null) ...[
        _color(
          'Gradient end',
          _draft.gradientEnd!,
          (value) => _draft.copyWith(gradientEnd: value),
        ),
        _slider(
          'Gradient angle',
          _draft.gradientAngle,
          360,
          (value) => _draft.copyWith(gradientAngle: value),
        ),
      ],
      _color(
        'Border',
        _draft.border,
        (value) => _draft.copyWith(border: value),
      ),
      _slider(
        'Border width',
        _draft.borderWidth,
        20,
        (value) => _draft.copyWith(borderWidth: value),
      ),
      _slider(
        'Corner radius',
        _draft.radius,
        160,
        (value) => _draft.copyWith(radius: value),
      ),
      _color(
        'Shadow',
        _draft.shadow,
        (value) => _draft.copyWith(shadow: value),
      ),
      _slider(
        'Shadow blur',
        _draft.shadowBlur,
        100,
        (value) => _draft.copyWith(shadowBlur: value),
      ),
      _slider(
        'Shadow offset',
        _draft.shadowY,
        100,
        (value) => _draft.copyWith(shadowY: value),
      ),
      _slider(
        'Background blur',
        _draft.backgroundBlur,
        80,
        (value) => _draft.copyWith(backgroundBlur: value),
      ),
      _color(
        'Text color',
        _draft.textColor ?? 0xffffffff,
        (value) => _draft.copyWith(textColor: value),
      ),
      _slider(
        'Font size',
        _draft.fontSize,
        160,
        (value) => _draft.copyWith(fontSize: value),
      ),
      if (_draft.fontAsset != null)
        Row(
          children: [
            Expanded(child: Text(_draft.fontAsset!.split('/').last).small()),
            GhostButton(
              onPressed: () => _commit(_draft.copyWith(fontAsset: null)),
              child: const Text('Inherit font').small(),
            ),
          ],
        ),
      const Gap(8),
      StudioSelect<int>(
        key: const ValueKey('style-font-weight'),
        value: _draft.fontWeight,
        values: [
          0,
          for (var weight = 100; weight <= 900; weight += 100) weight,
        ],
        formatValue: (weight) =>
            weight == 0 ? 'Inherit weight' : 'Weight $weight',
        onChanged: (weight) => _commit(_draft.copyWith(fontWeight: weight)),
      ),
      const Gap(12),
      _slider(
        'Letter spacing',
        _draft.letterSpacing ?? 0,
        16,
        (value) => _draft.copyWith(letterSpacing: value),
        minimum: -4,
      ),
      _slider(
        'Line height',
        _draft.lineHeight ?? 1.2,
        3,
        (value) => _draft.copyWith(lineHeight: value),
        minimum: .5,
      ),
      _slider(
        'Opacity',
        _draft.opacity,
        1,
        (value) => _draft.copyWith(opacity: value),
      ),
    ],
  );
}
