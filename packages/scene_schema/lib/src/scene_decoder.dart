import 'dart:convert';

import 'scene_color_codec.dart';
import 'scene_document.dart';
import 'scene_json_reader.dart';
import 'scene_layout.dart';
import 'scene_node_decoder.dart';
import 'scene_shader.dart';
import 'scene_style.dart';

/// Decodes a scene document from its JSON authoring form.
///
/// Tooling and code generation share this boundary for shape, enum, layout,
/// and asset-path checks. Production consumes the resulting generated Dart
/// instead of parsing JSON during login.
SceneDocument decodeSceneDocument(String source) {
  final Object? decoded = jsonDecode(source);
  if (decoded is! JsonMap) {
    throw const FormatException('Scene document root must be a JSON object.');
  }
  final version = getInt(decoded, 'version');
  if (version < 1 || version > currentSceneVersion) {
    throw FormatException('Unsupported scene version: $version');
  }

  final nodeIds = <String>{};
  final nodes = <SceneNode>[
    for (final rawNode in getList(decoded, 'nodes'))
      decodeSceneNode(getMapValue(rawNode, 'nodes[]'), nodeIds, version),
  ];
  if (nodes.isEmpty) {
    throw const FormatException(
      'Scene document must contain at least one node.',
    );
  }
  _validateHierarchy(nodes);
  _validateHugSizing(nodes);

  final styles = {
    for (final entry in getMap(
      decoded,
      'styleTokens',
      fallback: const {},
    ).entries)
      entry.key: _decodeStyle(
        getMapValue(entry.value, 'styleTokens.${entry.key}'),
      ),
  };
  for (final node in nodes) {
    if (node.styleToken != null && !styles.containsKey(node.styleToken)) {
      throw FormatException(
        'Node ${node.id} references missing style token ${node.styleToken}.',
      );
    }
  }

  return SceneDocument(
    id: getString(decoded, 'id'),
    version: currentSceneVersion,
    canvas: _decodeCanvas(getMap(decoded, 'canvas')),
    background: _decodeBackground(getMap(decoded, 'background')),
    nodes: nodes,
    styleTokens: styles,
    guides: [
      for (final value
          in decoded['guides'] == null
              ? const <Object?>[]
              : getList(decoded, 'guides'))
        _decodeGuide(getMapValue(value, 'guides[]')),
    ],
    themeProperties: {
      for (final entry in getMap(
        decoded,
        'themeProperties',
        fallback: const {},
      ).entries)
        getNonEmptyKey(entry.key, 'themeProperties'): getStringValue(
          entry.value,
          'themeProperties.${entry.key}',
        ),
    },
  );
}

void _validateHugSizing(List<SceneNode> nodes) {
  for (final node in nodes) {
    for (final sizing in [
      node.sizing,
      ...node.breakpoints.map((rule) => rule.sizing).whereType<SceneSizing>(),
    ]) {
      if ((sizing.widthMode == SceneSizeMode.hug ||
              sizing.heightMode == SceneSizeMode.hug) &&
          node.layout == null &&
          node.primitive != ScenePrimitive.text) {
        throw const FormatException(
          'Hug sizing requires a frame or primitive text.',
        );
      }
    }
  }
}

void _validateHierarchy(List<SceneNode> nodes) {
  final byId = {for (final node in nodes) node.id: node};
  final checked = <String>{};
  for (final node in nodes) {
    var current = node;
    final path = <String>{};
    while (!checked.contains(current.id)) {
      if (!path.add(current.id)) {
        throw FormatException('Cyclic frame hierarchy at ${current.id}.');
      }
      final parentId = current.parentId;
      if (parentId == null) break;
      final parent = byId[parentId];
      if (parent == null || parent.layout == null) {
        throw FormatException(
          'Node ${current.id} requires a frame parent: $parentId.',
        );
      }
      current = parent;
    }
    checked.addAll(path);
  }
}

SceneCanvas _decodeCanvas(JsonMap json) {
  const defaults = SceneCanvas();
  final referenceWidth = getInt(
    json,
    'referenceWidth',
    fallback: defaults.referenceWidth,
  );
  final referenceHeight = getInt(
    json,
    'referenceHeight',
    fallback: defaults.referenceHeight,
  );
  if (referenceWidth < 1 ||
      referenceWidth > 16384 ||
      referenceHeight < 1 ||
      referenceHeight > 16384) {
    throw const FormatException(
      'Canvas reference dimensions must be between 1 and 16384 pixels.',
    );
  }
  return SceneCanvas(
    fit: getEnumValue(
      SceneCanvasFit.values,
      getString(json, 'fit'),
      'canvas.fit',
    ),
    useSafeArea: getBool(json, 'useSafeArea', fallback: defaults.useSafeArea),
    referenceWidth: referenceWidth,
    referenceHeight: referenceHeight,
  );
}

SceneBackground _decodeBackground(JsonMap json) {
  const defaults = SceneBackground(kind: SceneBackgroundKind.solid);
  final kind = getEnumValue(
    SceneBackgroundKind.values,
    getString(json, 'kind'),
    'background.kind',
  );
  final asset = findString(json, 'asset');
  if (asset != null) {
    validateSceneAssetPath(asset);
  }
  final scrimOpacity = getDouble(
    json,
    'scrimOpacity',
    fallback: defaults.scrimOpacity,
  );
  if (scrimOpacity < 0 || scrimOpacity > 1) {
    throw FormatException('background.scrimOpacity must be in [0, 1].');
  }
  final blurSigma = getDouble(json, 'blurSigma', fallback: defaults.blurSigma);
  if (blurSigma < 0) {
    throw FormatException('background.blurSigma must be >= 0.');
  }
  final parameters = getMap(json, 'parameters', fallback: const {});
  return SceneBackground(
    kind: kind,
    asset: asset,
    color: json['color'] == null
        ? defaults.color
        : decodeSceneColor(getString(json, 'color')),
    scrimOpacity: scrimOpacity,
    blurSigma: blurSigma,
    rendererId: findString(json, 'rendererId'),
    shader: json['shader'] == null
        ? null
        : _decodeShader(getMap(json, 'shader')),
    parameters: {
      for (final key in parameters.keys) key: getDouble(parameters, key),
    },
  );
}

SceneShader _decodeShader(JsonMap json) {
  final asset = getString(json, 'asset');
  validateSceneAssetPath(asset);
  final names = <String>{};
  String readBindingName(JsonMap value) {
    final name = getString(value, 'name');
    if (name.trim().isEmpty || !names.add(name)) {
      throw const FormatException(
        'Shader binding names must be nonempty and unique.',
      );
    }
    return name;
  }

  return SceneShader(
    asset: asset,
    uniforms: [
      for (final raw in getList(json, 'uniforms'))
        _decodeShaderUniform(raw, readBindingName),
    ],
    textures: [
      for (final raw
          in json['textures'] == null
              ? const <Object?>[]
              : getList(json, 'textures'))
        _decodeShaderTexture(raw, readBindingName),
    ],
  );
}

SceneShaderUniform _decodeShaderUniform(
  Object? raw,
  String Function(JsonMap) readBindingName,
) {
  final value = getMapValue(raw, 'uniforms[]');
  return SceneShaderUniform(
    name: readBindingName(value),
    source: getEnumValue(
      SceneUniformSource.values,
      getString(value, 'source', fallback: 'constant'),
      'uniform.source',
    ),
    value: getDouble(value, 'value', fallback: 0),
    scale: getDouble(value, 'scale', fallback: 1),
  );
}

SceneShaderTexture _decodeShaderTexture(
  Object? raw,
  String Function(JsonMap) readBindingName,
) {
  final value = getMapValue(raw, 'textures[]');
  final asset = getString(value, 'asset');
  validateSceneAssetPath(asset);
  return SceneShaderTexture(name: readBindingName(value), asset: asset);
}

SceneGuide _decodeGuide(JsonMap json) {
  final position = getDouble(json, 'position');
  if (position < 0 || position > 1) {
    throw const FormatException('Guide position must be in [0, 1].');
  }
  return SceneGuide(
    axis: getEnumValue(
      SceneGuideAxis.values,
      getString(json, 'axis'),
      'guide.axis',
    ),
    position: position,
  );
}

SceneStyle _decodeStyle(JsonMap json) {
  const defaults = SceneStyle();
  int color(String key, int fallback) =>
      json[key] == null ? fallback : decodeSceneColor(getString(json, key));
  final opacity = getDouble(json, 'opacity', fallback: 1);
  if (opacity < 0 || opacity > 1) {
    throw const FormatException('Style opacity must be in [0, 1].');
  }
  final fontAsset = findString(json, 'fontAsset');
  if (fontAsset != null) validateSceneAssetPath(fontAsset);
  final weight = getInt(json, 'fontWeight', fallback: 0);
  final height = json['lineHeight'] == null
      ? null
      : getDouble(json, 'lineHeight');
  if ((weight != 0 && (weight < 100 || weight > 900 || weight % 100 != 0)) ||
      (height != null && height <= 0)) {
    throw const FormatException(
      'Typography requires a weight of 100..900 or 0 to inherit, and a positive line height.',
    );
  }
  return SceneStyle(
    fill: color('fill', defaults.fill),
    gradientEnd: json['gradientEnd'] == null ? null : color('gradientEnd', 0),
    gradientAngle: getDouble(
      json,
      'gradientAngle',
      fallback: defaults.gradientAngle,
    ),
    border: color('border', defaults.border),
    borderWidth: getNonNegative(json, 'borderWidth'),
    radius: getNonNegative(json, 'radius'),
    shadow: color('shadow', defaults.shadow),
    shadowBlur: getNonNegative(json, 'shadowBlur'),
    shadowY: getDouble(json, 'shadowY', fallback: defaults.shadowY),
    backgroundBlur: getNonNegative(json, 'backgroundBlur'),
    textColor: json['textColor'] == null ? null : color('textColor', 0),
    fontSize: getNonNegative(json, 'fontSize'),
    fontAsset: fontAsset,
    fontWeight: weight,
    lineHeight: height,
    letterSpacing: json['letterSpacing'] == null
        ? null
        : getDouble(json, 'letterSpacing'),
    opacity: opacity,
  );
}
