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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: StudioFormSection(
              title: 'Background effects',
              spacing: 12,
              children: [
                OutlineButton(
                  key: const ValueKey('open-shader-playground'),
                  density: ButtonDensity.dense,
                  onPressed: () => showOverlay<void>(
                    context,
                    const DialogConfiguration(),
                    builder: (_) => StudioShaderPlayground(
                      editor: widget.editor,
                      assets: widget.assets,
                      onAssetsChanged: widget.onAssetsChanged,
                    ),
                  ),
                  child: const Text('Shader Playground').small(),
                ),
                if (_draft.shader != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(_draft.shader!.asset.split('/').last)
                            .xSmall()
                            .muted(),
                      ),
                      GhostButton(
                        density: ButtonDensity.dense,
                        onPressed: () =>
                            _commit(_draft.copyWith(shader: null)),
                        child: const Text('Remove authored shader').small(),
                      ),
                    ],
                  ),
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
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: renderer != null && renderer.parameters.isNotEmpty
                ? StudioFormSection(
                    title: 'Shader parameters',
                    spacing: 12,
                    children: [
                      const Text('Use Preview to animate speed and flow.')
                          .xSmall()
                          .muted(),
                      for (final parameter in renderer.parameters)
                        _slider(
                          parameter.id,
                          parameter.label,
                          parameter.getValue(_draft),
                          parameter.minimum,
                          parameter.maximum,
                          (value) => _draft.copyWith(
                            parameters: {
                              ..._draft.parameters,
                              parameter.id: value,
                            },
                          ),
                        ),
                    ],
                  )
                : const Text(
                    'This background has no declared shader parameters.',
                  ).xSmall().muted(),
          ),
        ],
      ),
    );
  }
}
