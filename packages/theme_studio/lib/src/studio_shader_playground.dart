import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_assets.dart';
import 'studio_form.dart';
import 'studio_shader_compiler.dart';

const studioShaderExample = '''#include <flutter/runtime_effect.glsl>
uniform vec2 resolution;
uniform float time;
uniform vec3 color;
out vec4 fragColor;
void main() {
  vec2 uv = FlutterFragCoord().xy / resolution;
  float wave = 0.5 + 0.5 * sin(time + uv.x * 6.0);
  fragColor = vec4(color * vec3(wave, uv.y, 1.0), 1.0);
}
''';

class StudioShaderPlayground extends StatefulWidget {
  const StudioShaderPlayground({
    required this.editor,
    required this.assets,
    required this.onAssetsChanged,
    super.key,
  });
  final SceneEditor editor;
  final StudioAssets assets;
  final VoidCallback onAssetsChanged;
  @override
  State<StudioShaderPlayground> createState() => _StudioShaderPlaygroundState();
}

class _StudioShaderPlaygroundState extends State<StudioShaderPlayground> {
  late final _source = TextEditingController(text: studioShaderExample);
  StudioCompiledShader? _compiled;
  ui.FragmentProgram? _program;
  List<SceneShaderUniform> _uniforms = [];
  List<SceneShaderTexture> _textures = [];
  final _values = <String, TextEditingController>{};
  final _scales = <String, TextEditingController>{};
  String? _selectedAsset;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final shader = widget.editor.document.background.shader;
    if (shader != null) {
      _selectedAsset = shader.asset;
      _uniforms = shader.uniforms;
      _textures = shader.textures;
      _loadSource(shader.asset);
    }
  }

  Future<void> _loadSource(String asset) async {
    setState(() => _busy = true);
    try {
      final source = await widget.assets.loadTextAsset(asset);
      if (mounted) {
        setState(() {
          _selectedAsset = asset;
          _source.text = source;
          _compiled = null;
          _program = null;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final compiled = await widget.assets.shaderCompiler.compile(
        _source.text,
        includeDirectory: _selectedAsset == null
            ? null
            : widget.assets.findFile(_selectedAsset!)?.parent,
      );
      final program = await widget.assets.shaderCompiler.loadCompiled(compiled);
      if (!mounted) return;
      final old = {for (final uniform in _uniforms) uniform.name: uniform};
      final textures = {
        for (final texture in _textures) texture.name: texture.asset,
      };
      final images = _getImages();
      setState(() {
        _compiled = compiled;
        _program = program;
        _uniforms = [
          for (final name in compiled.uniformNames)
            old[name] ?? getDefaultShaderUniform(name),
        ];
        _textures = [
          for (final name in compiled.textureNames)
            SceneShaderTexture(
              name: name,
              asset: textures[name] ?? images.firstOrNull ?? '',
            ),
        ];
        for (final uniform in _uniforms) {
          _values.putIfAbsent(uniform.name, TextEditingController.new).text =
              '${uniform.value}';
          _scales.putIfAbsent(uniform.name, TextEditingController.new).text =
              '${uniform.scale}';
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _getImages() => widget.assets
      .getAssets()
      .where(
        (asset) =>
            getStudioAssetKind(asset) == StudioAssetKind.image ||
            getStudioAssetKind(asset) == StudioAssetKind.material,
      )
      .toList();
  void _updateUniform(int index) {
    final uniform = _uniforms[index];
    final value = double.tryParse(_values[uniform.name]!.text);
    final scale = double.tryParse(_scales[uniform.name]!.text);
    if (value == null || !value.isFinite || scale == null || !scale.isFinite) {
      return;
    }
    setState(
      () =>
          _uniforms = [..._uniforms]
            ..[index] = uniform.copyWith(value: value, scale: scale),
    );
  }

  Future<void> _apply() async {
    final compiled = _compiled;
    final program = _program;
    if (compiled == null ||
        program == null ||
        compiled.source != _source.text) {
      return;
    }
    if (!widget.editor.applyDraft()) return;
    setState(() => _busy = true);
    Directory? staging;
    try {
      for (final uniform in _uniforms) {
        final value = double.tryParse(_values[uniform.name]!.text);
        final scale = double.tryParse(_scales[uniform.name]!.text);
        if (value == null ||
            !value.isFinite ||
            scale == null ||
            !scale.isFinite) {
          throw FormatException('${uniform.name}: enter finite numbers.');
        }
      }
      if (_textures.any((texture) => texture.asset.isEmpty)) {
        throw const FormatException(
          'Choose an image for each sampler before applying.',
        );
      }
      staging = await Directory.systemTemp.createTemp('akari-shader-source-');
      final source = File('${staging.path}/playground.frag');
      await source.writeAsString(compiled.source);
      final origin = _selectedAsset == null
          ? null
          : widget.assets.findFile(_selectedAsset!);
      final asset = widget.assets.importFile(
        source,
        shader: true,
        targetDirectory: origin?.parent,
      );
      widget.assets.shaderCompiler.retainProgram(asset, compiled, program);
      widget.editor.updateScene(
        background: widget.editor.document.background.copyWith(
          kind: SceneBackgroundKind.custom,
          shader: SceneShader(
            asset: asset,
            uniforms: _uniforms,
            textures: _textures,
          ),
        ),
      );
      widget.onAssetsChanged();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (staging != null) await staging.delete(recursive: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _source.dispose();
    for (final field in [..._values.values, ..._scales.values]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<ui.FragmentProgram> _getPreviewProgram(String asset) =>
      Future.value(_program!);

  Widget _buildPreview() => AspectRatio(
    aspectRatio: 2,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ColoredBox(
        color: const Color(0xff171720),
        child: _program == null
            ? const Center(child: Text('Compile to preview'))
            : _textures.any((texture) => texture.asset.isEmpty)
            ? const Center(child: Text('Choose an image for each sampler'))
            : SceneShaderBackground(
                key: ObjectKey(_program),
                shader: SceneShader(
                  asset: 'assets/studio-preview.frag',
                  uniforms: _uniforms,
                  textures: _textures
                      .where((texture) => texture.asset.isNotEmpty)
                      .toList(),
                ),
                loadProgram: _getPreviewProgram,
                resolveImage: widget.assets.getImageProvider,
                onError: (error) {
                  if (mounted) setState(() => _error = error);
                },
              ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final shaders = widget.assets
        .getAssets()
        .where((asset) => asset.endsWith('.frag'))
        .toList();
    final images = _getImages();
    final current = _compiled?.source == _source.text;
    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioSelect<String>(
          key: const ValueKey('shader-source-asset'),
          value: shaders.contains(_selectedAsset) ? _selectedAsset : null,
          values: shaders,
          placeholder: const Text('Load a theme shader'),
          formatValue: (asset) => asset.split('/').last,
          enabled: !_busy,
          onChanged: _loadSource,
        ),
        const Gap(8),
        TextField(
          key: const ValueKey('shader-source'),
          controller: _source,
          maxLines: 14,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          onChanged: (_) => setState(() {}),
        ),
        const Gap(8),
        OutlineButton(
          key: const ValueKey('shader-compile'),
          onPressed: _busy ? null : _compile,
          child: Text(_busy ? 'Compiling…' : 'Compile and preview'),
        ),
      ],
    );
    return AlertDialog(
      title: const Text('Shader Playground'),
      content: SizedBox(
        width: 1000,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(160, MediaQuery.sizeOf(context).height - 200),
          ),
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (constraints.maxWidth >= 780)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: editor),
                        const Gap(16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildPreview(),
                              const Gap(8),
                              const Text(
                                'Bind float/vector components to constants, time, viewport, pointer or semantic state.',
                              ).small().muted(),
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    editor,
                    const Gap(12),
                    _buildPreview(),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: SelectableText(
                        _error!,
                        key: const ValueKey('shader-diagnostic'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.destructive,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (_compiled != null && !current)
                    const Text('Source changed. Compile again before applying.')
                        .small()
                        .muted(),
                  if (_program != null) ...[
                    const Gap(16),
                    const Text('Uniform bindings').small().semiBold(),
                    const Gap(8),
                    for (var index = 0; index < _uniforms.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_uniforms[index].name).small().semiBold(),
                            const Gap(4),
                            StudioEnumSelect(
                              value: _uniforms[index].source,
                              values: SceneUniformSource.values,
                              onChanged: (source) => setState(
                                () => _uniforms = [..._uniforms]
                                  ..[index] = _uniforms[index].copyWith(
                                    source: source,
                                  ),
                              ),
                            ),
                            const Gap(6),
                            StudioFieldRow(
                              left: StudioFormField(
                                label: 'Value / offset',
                                controller: _values[_uniforms[index].name]!,
                                inputKey: ValueKey('shader-value-$index'),
                                onChanged: (_) => _updateUniform(index),
                              ),
                              right: StudioFormField(
                                label: 'Scale',
                                controller: _scales[_uniforms[index].name]!,
                                inputKey: ValueKey('shader-scale-$index'),
                                onChanged: (_) => _updateUniform(index),
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (var index = 0; index < _textures.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Sampler: ${_textures[index].name}').small(),
                            const Gap(6),
                            StudioSelect<String>(
                              value: images.contains(_textures[index].asset)
                                  ? _textures[index].asset
                                  : null,
                              values: images,
                              placeholder: const Text('Choose image'),
                              formatValue: (asset) => asset.split('/').last,
                              onChanged: (asset) => setState(
                                () => _textures = [..._textures]
                                  ..[index] = SceneShaderTexture(
                                    name: _textures[index].name,
                                    asset: asset,
                                  ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        PrimaryButton(
          key: const ValueKey('shader-apply'),
          onPressed: _busy || !current || _program == null ? null : _apply,
          child: const Text('Apply as new shader'),
        ),
      ],
    );
  }
}
