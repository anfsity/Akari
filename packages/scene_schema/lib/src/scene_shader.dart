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

  @override
  bool operator ==(Object other) =>
      other is SceneShaderUniform &&
      other.name == name &&
      other.source == source &&
      other.value == value &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(name, source, value, scale);
}

class SceneShaderTexture {
  const SceneShaderTexture({required this.name, required this.asset});
  final String name;
  final String asset;

  @override
  bool operator ==(Object other) =>
      other is SceneShaderTexture && other.name == name && other.asset == asset;

  @override
  int get hashCode => Object.hash(name, asset);
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

  @override
  bool operator ==(Object other) =>
      other is SceneShader &&
      other.asset == asset &&
      _shaderListEquals(other.uniforms, uniforms) &&
      _shaderListEquals(other.textures, textures);

  @override
  int get hashCode => Object.hash(
    asset,
    Object.hashAll(uniforms),
    Object.hashAll(textures),
  );
}

bool _shaderListEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
