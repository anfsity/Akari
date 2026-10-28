import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_form.dart';
import 'studio_assets.dart';
import 'studio_shader_playground.dart';

class StudioEffectsInspector extends StatefulWidget {
  const StudioEffectsInspector({
    required this.editor,
    required this.theme,
    required this.assets,
    required this.onAssetsChanged,
    super.key,
  });
  final SceneEditor editor;
  final ThemeDefinition theme;
  final StudioAssets assets;
  final VoidCallback onAssetsChanged;
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
  ) => StudioSliderField(
    sliderKey: ValueKey('effect-$id'),
    label: label,
    value: value,
    minimum: minimum,
    maximum: maximum,
    decimals: 2,
    onPreview: (value) => _preview(update(value)),
    onCommit: (value) => _commit(update(value)),
    onCancel: _cancel,
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
          const Gap(12),
          OutlineButton(
            key: const ValueKey('open-shader-playground'),
            onPressed: () => showOverlay<void>(
              context,
              const DialogConfiguration(),
              builder: (_) => StudioShaderPlayground(
                editor: widget.editor,
                assets: widget.assets,
                onAssetsChanged: widget.onAssetsChanged,
              ),
            ),
            child: const Text('Shader Playground'),
          ),
          if (_draft.shader != null) ...[
            const Gap(8),
            Text(_draft.shader!.asset.split('/').last).small().muted(),
            GhostButton(
              onPressed: () => _commit(_draft.copyWith(shader: null)),
              child: const Text('Remove authored shader').small(),
            ),
          ],
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
