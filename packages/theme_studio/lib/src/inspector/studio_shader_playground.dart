import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../resources/studio_assets.dart';
import '../resources/studio_shader_compiler.dart';
import '../ui/studio_form.dart';

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
  late List<String> _shaders;
  late List<String> _images;
  String? _selectedAsset;
  String? _error;
  bool _busy = false;
  int _loadGeneration = 0;

  void _refreshAssetLists() {
    final assets = widget.assets.getAssets();
    _shaders = assets.where((asset) => asset.endsWith('.frag')).toList();
    _images = assets
        .where(
          (asset) =>
              getStudioAssetKind(asset) == StudioAssetKind.image ||
              getStudioAssetKind(asset) == StudioAssetKind.material,
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _refreshAssetLists();
    final shader = widget.editor.document.background.shader;
    if (shader != null) {
      _selectedAsset = shader.asset;
      _uniforms = shader.uniforms;
      _textures = shader.textures;
      _busy = true;
      _loadSource(shader.asset, initial: true);
    }
  }

  @override
  void didUpdateWidget(StudioShaderPlayground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.assets, widget.assets)) {
      _refreshAssetLists();
    }
  }

  Future<void> _loadSource(String asset, {bool initial = false}) async {
    final generation = ++_loadGeneration;
    if (!initial) {
      setState(() => _busy = true);
    }
    try {
      final source = await widget.assets.loadTextAsset(asset);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _selectedAsset = asset;
        _source.text = source;
        _compiled = null;
        _program = null;
        _error = null;
      });
    } on Object catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _compile() async {
    final generation = ++_loadGeneration;
    setState(() {
      _busy = true;
      _error = null;
      _compiled = null;
    });
    try {
      final compiled = await widget.assets.shaderCompiler.compile(
        _source.text,
        includeDirectory: _selectedAsset == null
            ? null
            : widget.assets.findFile(_selectedAsset!)?.parent,
      );
      final program = await widget.assets.shaderCompiler.loadCompiled(compiled);
      if (!mounted || generation != _loadGeneration) return;
      final old = {for (final uniform in _uniforms) uniform.name: uniform};
      final textures = {
        for (final texture in _textures) texture.name: texture.asset,
      };
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
              asset: textures[name] ?? _images.firstOrNull ?? '',
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
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _busy = false);
      }
    }
  }

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
    final editor = widget.editor;
    if (!editor.tryApplyDraft()) return;
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
      final candidateBackground = editor.document.background.copyWith(
        kind: SceneBackgroundKind.custom,
        shader: SceneShader(
          asset: 'packages/${widget.assets.packageName}/assets/playground.frag',
          uniforms: _uniforms,
          textures: _textures,
        ),
      );
      // Validate before importing files or editing pubspec.yaml so invalid
      // scene updates leave assets and the manifest untouched.
      editor.validateScene(background: candidateBackground);
      staging = await Directory.systemTemp.createTemp('akari-shader-source-');
      if (!mounted || editor.isDisposed) return;
      final source = File('${staging.path}/playground.frag');
      await source.writeAsString(compiled.source);
      if (!mounted || editor.isDisposed) return;
      final origin = _selectedAsset == null
          ? null
          : widget.assets.findFile(_selectedAsset!);
      final asset = widget.assets.importFile(
        source,
        shader: true,
        targetDirectory: origin?.parent,
      );
      widget.assets.shaderCompiler.retainProgram(asset, compiled, program);
      editor.updateScene(
        background: candidateBackground.copyWith(
          shader: candidateBackground.shader!.copyWith(asset: asset),
        ),
      );
      widget.onAssetsChanged();
      Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final sourcePanel = _ShaderSourcePanel(
      selectedAsset: _selectedAsset,
      shaders: _shaders,
      sourceController: _source,
      busy: _busy,
      onLoadSource: _loadSource,
      onCompile: _compile,
    );
    final previewPane = _ShaderPreviewPane(
      program: _program,
      uniforms: _uniforms,
      textures: _textures,
      loadProgram: _getPreviewProgram,
      resolveImage: widget.assets.getImageProvider,
      onError: (error) {
        if (mounted) setState(() => _error = error);
      },
    );
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
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
                          Expanded(child: sourcePanel),
                          const Gap(16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                previewPane,
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
                      sourcePanel,
                      const Gap(12),
                      previewPane,
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
                    if (_compiled case final compiled?)
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _source,
                        builder: (context, value, _) =>
                            compiled.source == value.text
                            ? const SizedBox.shrink()
                            : const Text(
                                'Source changed. Compile again before applying.',
                              ).small().muted(),
                      ),
                    if (_program != null) ...[
                      const Gap(16),
                      const Text('Uniform bindings').small().semiBold(),
                      const Gap(8),
                      _ShaderUniformBindings(
                        uniforms: _uniforms,
                        values: _values,
                        scales: _scales,
                        onSourceChanged: (index, source) => setState(
                          () => _uniforms = [..._uniforms]
                            ..[index] = _uniforms[index].copyWith(
                              source: source,
                            ),
                        ),
                        onValueChanged: _updateUniform,
                      ),
                      _ShaderSamplerBindings(
                        textures: _textures,
                        images: _images,
                        onChanged: (index, asset) => setState(
                          () => _textures = [..._textures]
                            ..[index] = SceneShaderTexture(
                              name: _textures[index].name,
                              asset: asset,
                            ),
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
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _source,
            builder: (context, value, _) {
              final current = _compiled?.source == value.text;
              return PrimaryButton(
                key: const ValueKey('shader-apply'),
                onPressed: _busy || !current || _program == null
                    ? null
                    : _apply,
                child: const Text('Apply as new shader'),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShaderSourcePanel extends StatelessWidget {
  const _ShaderSourcePanel({
    required this.selectedAsset,
    required this.shaders,
    required this.sourceController,
    required this.busy,
    required this.onLoadSource,
    required this.onCompile,
  });

  final String? selectedAsset;
  final List<String> shaders;
  final TextEditingController sourceController;
  final bool busy;
  final ValueChanged<String> onLoadSource;
  final VoidCallback onCompile;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StudioSelect<String>(
        key: const ValueKey('shader-source-asset'),
        value: shaders.contains(selectedAsset) ? selectedAsset : null,
        values: shaders,
        placeholder: const Text('Load a theme shader'),
        formatValue: (asset) => asset.split('/').last,
        enabled: !busy,
        onChanged: onLoadSource,
      ),
      const Gap(8),
      TextField(
        key: const ValueKey('shader-source'),
        controller: sourceController,
        maxLines: 14,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      const Gap(8),
      OutlineButton(
        key: const ValueKey('shader-compile'),
        onPressed: busy ? null : onCompile,
        child: Text(busy ? 'Compiling…' : 'Compile and preview'),
      ),
    ],
  );
}

class _ShaderPreviewPane extends StatelessWidget {
  const _ShaderPreviewPane({
    required this.program,
    required this.uniforms,
    required this.textures,
    required this.loadProgram,
    required this.resolveImage,
    required this.onError,
  });

  final ui.FragmentProgram? program;
  final List<SceneShaderUniform> uniforms;
  final List<SceneShaderTexture> textures;
  final Future<ui.FragmentProgram> Function(String) loadProgram;
  final ImageProvider Function(String) resolveImage;
  final ValueChanged<String> onError;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 2,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ColoredBox(
        color: const Color(0xff171720),
        child: program == null
            ? const Center(child: Text('Compile to preview'))
            : textures.any((texture) => texture.asset.isEmpty)
            ? const Center(child: Text('Choose an image for each sampler'))
            : SceneShaderBackground(
                key: ObjectKey(program),
                shader: SceneShader(
                  asset: 'assets/studio-preview.frag',
                  uniforms: uniforms,
                  textures: textures
                      .where((texture) => texture.asset.isNotEmpty)
                      .toList(),
                ),
                loadProgram: loadProgram,
                resolveImage: resolveImage,
                onError: onError,
              ),
      ),
    ),
  );
}

class _ShaderUniformBindings extends StatelessWidget {
  const _ShaderUniformBindings({
    required this.uniforms,
    required this.values,
    required this.scales,
    required this.onSourceChanged,
    required this.onValueChanged,
  });

  final List<SceneShaderUniform> uniforms;
  final Map<String, TextEditingController> values;
  final Map<String, TextEditingController> scales;
  final void Function(int index, SceneUniformSource source) onSourceChanged;
  final ValueChanged<int> onValueChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < uniforms.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(uniforms[index].name).small().semiBold(),
              const Gap(4),
              StudioEnumSelect(
                value: uniforms[index].source,
                values: SceneUniformSource.values,
                onChanged: (source) => onSourceChanged(index, source),
              ),
              const Gap(6),
              StudioFieldRow(
                left: StudioFormField(
                  label: 'Value / offset',
                  controller: values[uniforms[index].name]!,
                  inputKey: ValueKey('shader-value-$index'),
                  onChanged: (_) => onValueChanged(index),
                ),
                right: StudioFormField(
                  label: 'Scale',
                  controller: scales[uniforms[index].name]!,
                  inputKey: ValueKey('shader-scale-$index'),
                  onChanged: (_) => onValueChanged(index),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _ShaderSamplerBindings extends StatelessWidget {
  const _ShaderSamplerBindings({
    required this.textures,
    required this.images,
    required this.onChanged,
  });

  final List<SceneShaderTexture> textures;
  final List<String> images;
  final void Function(int index, String asset) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < textures.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sampler: ${textures[index].name}').small(),
              const Gap(6),
              StudioSelect<String>(
                value: images.contains(textures[index].asset)
                    ? textures[index].asset
                    : null,
                values: images,
                placeholder: const Text('Choose image'),
                formatValue: (asset) => asset.split('/').last,
                onChanged: (asset) => onChanged(index, asset),
              ),
            ],
          ),
        ),
    ],
  );
}
