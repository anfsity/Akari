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
  bool _hasSliderDraft = false;
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
    _hasSliderDraft = false;
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
    SceneStyle Function(double) update,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label  ${value.toStringAsFixed(1)}').small().muted(),
        const Gap(6),
        Listener(
          // shadcn omits onChangeEnd when a controlled slider already equals
          // its final value. Pointer release still commits the live preview.
          onPointerUp: (_) {
            if (_hasSliderDraft) _commit(_draft);
          },
          onPointerCancel: (_) {
            _hasSliderDraft = false;
            widget.editor.cancelPreview();
            setState(_updateDraft);
          },
          child: Slider(
            key: ValueKey('style-$label'),
            value: SliderValue.single(value.clamp(0, maximum)),
            max: maximum,
            onChanged: (value) {
              _hasSliderDraft = true;
              _preview(update(value.value));
            },
            onChangeEnd: (value) => _commit(update(value.value)),
          ),
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
      _slider(
        'Opacity',
        _draft.opacity,
        1,
        (value) => _draft.copyWith(opacity: value),
      ),
    ],
  );
}
