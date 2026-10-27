import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_form.dart';

class StudioEffectsInspector extends StatefulWidget {
  const StudioEffectsInspector({
    required this.editor,
    required this.theme,
    super.key,
  });
  final SceneEditor editor;
  final ThemeDefinition theme;
  @override
  State<StudioEffectsInspector> createState() => _StudioEffectsInspectorState();
}

class _StudioEffectsInspectorState extends State<StudioEffectsInspector> {
  late SceneBackground _draft;
  late SceneBackground _source;
  @override
  void initState() {
    super.initState();
    _source = _draft = widget.editor.document.background;
    widget.editor.addListener(_updateSource);
  }

  @override
  void didUpdateWidget(StudioEffectsInspector old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor) {
      old.editor.removeListener(_updateSource);
      widget.editor.addListener(_updateSource);
      _source = _draft = widget.editor.document.background;
    }
  }

  void _updateSource() {
    if (identical(_source, widget.editor.document.background)) return;
    setState(() => _source = _draft = widget.editor.document.background);
  }

  void _preview(SceneBackground background) {
    setState(() => _draft = background);
    widget.editor.previewBackground(background);
  }

  void _commit(SceneBackground background) =>
      widget.editor.updateScene(background: background);
  void _cancel() {
    widget.editor.cancelPreview();
    setState(() => _draft = _source);
  }

  @override
  void dispose() {
    widget.editor.removeListener(_updateSource);
    super.dispose();
  }

  Widget _slider(
    String id,
    String label,
    double value,
    double minimum,
    double maximum,
    SceneBackground Function(double) update,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label  ${value.toStringAsFixed(2)}').small().muted(),
        const Gap(8),
        StudioPreviewSlider(
          key: ValueKey('effect-$id'),
          value: value,
          minimum: minimum,
          maximum: maximum,
          onPreview: (value) => _preview(update(value)),
          onCommit: (value) => _commit(update(value)),
          onCancel: _cancel,
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final renderer = widget.theme.bundle.backgrounds[_draft.kind];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Background effects').semiBold(),
          const Gap(16),
          _slider(
            'blur',
            'Blur',
            _draft.blurSigma,
            0,
            80,
            (value) => _draft.copyWith(blurSigma: value),
          ),
          _slider(
            'scrim',
            'Scrim opacity',
            _draft.scrimOpacity,
            0,
            1,
            (value) => _draft.copyWith(scrimOpacity: value),
          ),
          if (renderer != null && renderer.parameters.isNotEmpty) ...[
            const Divider(),
            const Gap(12),
            const Text('Shader parameters').small().semiBold(),
            const Text('Use Preview to animate speed and flow.')
                .small()
                .muted(),
            const Gap(16),
            for (final parameter in renderer.parameters)
              _slider(
                parameter.id,
                parameter.label,
                parameter.getValue(_draft),
                parameter.minimum,
                parameter.maximum,
                (value) => _draft.copyWith(
                  parameters: {..._draft.parameters, parameter.id: value},
                ),
              ),
          ] else
            const Text('This background has no declared shader parameters.')
                .small()
                .muted(),
        ],
      ),
    );
  }
}
