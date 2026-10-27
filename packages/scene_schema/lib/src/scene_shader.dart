/// A float's source is explicit; vectors occupy consecutive float slots in
/// compiler reflection order. Scale/offset also apply to dynamic bindings.
enum SceneUniformSource {
  constant,
  time,
  width,
  height,
  pointerX,
  pointerY,
  dormant,
  authError,
}

class SceneShaderUniform {
  const SceneShaderUniform({
    required this.name,
    this.source = SceneUniformSource.constant,
    this.value = 0,
    this.scale = 1,
  });
  final String name;
  final SceneUniformSource source;
  final double value;
  final double scale;
  SceneShaderUniform copyWith({
    SceneUniformSource? source,
    double? value,
    double? scale,
  }) => SceneShaderUniform(
    name: name,
    source: source ?? this.source,
    value: value ?? this.value,
    scale: scale ?? this.scale,
  );
}

class SceneShaderTexture {
  const SceneShaderTexture({required this.name, required this.asset});
  final String name;
  final String asset;
}

class SceneShader {
  const SceneShader({
    required this.asset,
    this.uniforms = const [],
    this.textures = const [],
  });
  final String asset;
  final List<SceneShaderUniform> uniforms;
  final List<SceneShaderTexture> textures;
  SceneShader copyWith({
    String? asset,
    List<SceneShaderUniform>? uniforms,
    List<SceneShaderTexture>? textures,
  }) => SceneShader(
    asset: asset ?? this.asset,
    uniforms: uniforms ?? this.uniforms,
    textures: textures ?? this.textures,
  );
}
