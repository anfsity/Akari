import 'dart:convert';

import 'package:build/build.dart';

enum SceneCanvasFit { cover, contain, reflow }

enum SceneBackgroundKind { image, solid, video, custom }

enum SceneNodeKind {
  background,
  glassPanel,
  avatar,
  accountName,
  accountPicker,
  sessionPicker,
  credentialField,
  primaryAction,
  secondaryAction,
  powerActions,
  dateTime,
  status,
  decoration,
}

enum SceneBinding {
  serviceMode,
  authMode,
  authPrompt,
  authError,
  accountUsers,
  accountSelected,
  sessionMode,
  sessionSessions,
  sessionSelected,
  continueEnabled,
  powerMode,
  powerError,
}

enum SceneAction {
  selectUser,
  selectSession,
  beginAuthentication,
  respondToPrompt,
  cancelAuthentication,
  requestPowerAction,
  retryAuthentication,
  retryPrompt,
  reconnectService,
  retrySessionCatalog,
  sleepGreeter,
}

enum SceneMotionPreset {
  none,
  fade,
  fadeSlide,
  fadeScale,
  hoverLift,
  focusGlow,
}

Builder sceneBuilder(BuilderOptions options) => SceneBuilder();

class SceneBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    '.scene.json': ['.scene.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = await buildStep.readAsString(buildStep.inputId);
    final outputId = buildStep.inputId.changeExtension('.g.dart');
    await buildStep.writeAsString(outputId, generateScene(input));
  }
}

String generateScene(String input) {
  final decoded = jsonDecode(input);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Scene document root must be a JSON object.');
  }

  final document = _parseDocument(decoded);
  return _generate(document);
}

class _SceneData {
  const _SceneData({
    required this.id,
    required this.version,
    required this.canvas,
    required this.background,
    required this.nodes,
  });

  final String id;
  final int version;
  final _CanvasData canvas;
  final _BackgroundData background;
  final List<_NodeData> nodes;
}

class _CanvasData {
  const _CanvasData({required this.fit, required this.useSafeArea});

  final SceneCanvasFit fit;
  final bool useSafeArea;
}

class _BackgroundData {
  const _BackgroundData({
    required this.kind,
    required this.asset,
    required this.color,
    required this.scrimOpacity,
    required this.blurSigma,
    required this.rendererId,
  });

  final SceneBackgroundKind kind;
  final String? asset;
  final String color;
  final double scrimOpacity;
  final double blurSigma;
  final String? rendererId;
}

class _NodeData {
  const _NodeData({
    required this.id,
    required this.kind,
    required this.rect,
    required this.transform,
    required this.z,
    required this.renderOrder,
    required this.focusOrder,
    required this.motion,
    required this.bindings,
    required this.action,
    required this.properties,
  });

  final String id;
  final SceneNodeKind kind;
  final _RectData rect;
  final _TransformData transform;
  final int z;
  final int renderOrder;
  final int focusOrder;
  final SceneMotionPreset motion;
  final List<SceneBinding> bindings;
  final SceneAction? action;
  final Map<String, String> properties;
}

class _RectData {
  const _RectData(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;
}

class _TransformData {
  const _TransformData({
    required this.translateX,
    required this.translateY,
    required this.scaleX,
    required this.scaleY,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
    required this.pivotX,
    required this.pivotY,
    required this.perspective,
  });

  final double translateX;
  final double translateY;
  final double scaleX;
  final double scaleY;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double pivotX;
  final double pivotY;
  final double perspective;
}

_SceneData _parseDocument(Map<String, dynamic> json) {
  final version = _int(json, 'version');
  if (version != 1) {
    throw FormatException('Unsupported scene version: $version');
  }

  final id = _string(json, 'id');
  final canvasJson = _map(json, 'canvas');
  final backgroundJson = _map(json, 'background');
  final nodesJson = _list(json, 'nodes');

  final nodeIds = <String>{};
  final nodes = <_NodeData>[
    for (final rawNode in nodesJson)
      _parseNode(_asMap(rawNode, 'nodes[]'), nodeIds),
  ];

  if (nodes.isEmpty) {
    throw const FormatException(
      'Scene document must contain at least one node.',
    );
  }

  return _SceneData(
    id: id,
    version: version,
    canvas: _CanvasData(
      fit: _enumValue(
        SceneCanvasFit.values,
        _string(canvasJson, 'fit'),
        'canvas.fit',
      ),
      useSafeArea: _bool(canvasJson, 'useSafeArea', fallback: true),
    ),
    background: _parseBackground(backgroundJson),
    nodes: nodes,
  );
}

_BackgroundData _parseBackground(Map<String, dynamic> json) {
  final kind = _enumValue(
    SceneBackgroundKind.values,
    _string(json, 'kind'),
    'background.kind',
  );
  final asset = _nullableString(json, 'asset');
  if (asset != null &&
      (asset.contains('..') ||
          (!asset.startsWith('assets/') &&
              kind == SceneBackgroundKind.image))) {
    throw FormatException('Invalid background asset path: $asset');
  }
  final color = _string(json, 'color', fallback: '#0d151a');
  _validateColor(color);
  final scrimOpacity = _double(json, 'scrimOpacity', fallback: 0.35);
  if (scrimOpacity < 0 || scrimOpacity > 1) {
    throw FormatException('background.scrimOpacity must be in [0, 1].');
  }
  final blurSigma = _double(json, 'blurSigma', fallback: 0);
  if (blurSigma < 0) {
    throw FormatException('background.blurSigma must be >= 0.');
  }
  return _BackgroundData(
    kind: kind,
    asset: asset,
    color: color,
    scrimOpacity: scrimOpacity,
    blurSigma: blurSigma,
    rendererId: _nullableString(json, 'rendererId'),
  );
}

_NodeData _parseNode(Map<String, dynamic> json, Set<String> nodeIds) {
  final id = _string(json, 'id');
  if (!nodeIds.add(id)) {
    throw FormatException('Duplicate scene node id: $id');
  }

  final rectJson = _map(json, 'rect');
  final rect = _RectData(
    _double(rectJson, 'x'),
    _double(rectJson, 'y'),
    _double(rectJson, 'width'),
    _double(rectJson, 'height'),
  );
  if (rect.x < 0 ||
      rect.y < 0 ||
      rect.width <= 0 ||
      rect.height <= 0 ||
      rect.x + rect.width > 1 ||
      rect.y + rect.height > 1) {
    throw FormatException('Node $id has a non-normalized rect.');
  }

  final transformJson = _map(json, 'transform', fallback: const {});
  final transform = _TransformData(
    translateX: _double(transformJson, 'translateX', fallback: 0),
    translateY: _double(transformJson, 'translateY', fallback: 0),
    scaleX: _double(transformJson, 'scaleX', fallback: 1),
    scaleY: _double(transformJson, 'scaleY', fallback: 1),
    rotationX: _double(transformJson, 'rotationX', fallback: 0),
    rotationY: _double(transformJson, 'rotationY', fallback: 0),
    rotationZ: _double(transformJson, 'rotationZ', fallback: 0),
    pivotX: _double(transformJson, 'pivotX', fallback: 0.5),
    pivotY: _double(transformJson, 'pivotY', fallback: 0.5),
    perspective: _double(transformJson, 'perspective', fallback: 0),
  );

  final bindings = <SceneBinding>[
    for (final value in _stringList(json, 'bindings', fallback: const []))
      _enumValue(SceneBinding.values, value, 'node.bindings'),
  ];
  final actionName = _nullableString(json, 'action');
  final properties = <String, String>{
    for (final entry in _map(json, 'properties', fallback: const {}).entries)
      entry.key: _asString(entry.value, 'node.properties.${entry.key}'),
  };

  return _NodeData(
    id: id,
    kind: _enumValue(SceneNodeKind.values, _string(json, 'kind'), 'node.kind'),
    rect: rect,
    transform: transform,
    z: _int(json, 'z', fallback: 0),
    renderOrder: _int(json, 'renderOrder', fallback: 0),
    focusOrder: _int(json, 'focusOrder', fallback: 0),
    motion: _enumValue(
      SceneMotionPreset.values,
      _string(json, 'motion', fallback: 'none'),
      'node.motion',
    ),
    bindings: bindings,
    action: actionName == null
        ? null
        : _enumValue(SceneAction.values, actionName, 'node.action'),
    properties: properties,
  );
}

String _generate(_SceneData document) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// Generated from ${document.id}.scene.json.')
    ..writeln("import 'package:flutter/material.dart';")
    ..writeln("import 'package:mozais_scene/mozais_scene.dart';")
    ..writeln()
    ..writeln(
      'final SceneDocument ${_variableName(document.id)} = SceneDocument(',
    )
    ..writeln('  id: ${_dartString(document.id)},')
    ..writeln('  version: ${document.version},')
    ..writeln('  canvas: const SceneCanvas(')
    ..writeln('    fit: SceneCanvasFit.${document.canvas.fit.name},')
    ..writeln('    useSafeArea: ${document.canvas.useSafeArea},')
    ..writeln('  ),')
    ..writeln('  background: SceneBackground(')
    ..writeln('    kind: SceneBackgroundKind.${document.background.kind.name},')
    ..writeln('    asset: ${_dartNullableString(document.background.asset)},')
    ..writeln('    color: ${_colorLiteral(document.background.color)},')
    ..writeln('    scrimOpacity: ${document.background.scrimOpacity},')
    ..writeln('    blurSigma: ${document.background.blurSigma},')
    ..writeln(
      '    rendererId: ${_dartNullableString(document.background.rendererId)},',
    )
    ..writeln('  ),')
    ..writeln('  nodes: <SceneNode>[');

  for (final node in document.nodes) {
    buffer
      ..writeln('    SceneNode(')
      ..writeln('      id: ${_dartString(node.id)},')
      ..writeln('      kind: SceneNodeKind.${node.kind.name},')
      ..writeln('      rect: const SceneRect(')
      ..writeln('        x: ${node.rect.x},')
      ..writeln('        y: ${node.rect.y},')
      ..writeln('        width: ${node.rect.width},')
      ..writeln('        height: ${node.rect.height},')
      ..writeln('      ),')
      ..writeln('      transform: const SceneTransform(')
      ..writeln('        translateX: ${node.transform.translateX},')
      ..writeln('        translateY: ${node.transform.translateY},')
      ..writeln('        scaleX: ${node.transform.scaleX},')
      ..writeln('        scaleY: ${node.transform.scaleY},')
      ..writeln('        rotationX: ${node.transform.rotationX},')
      ..writeln('        rotationY: ${node.transform.rotationY},')
      ..writeln('        rotationZ: ${node.transform.rotationZ},')
      ..writeln('        pivotX: ${node.transform.pivotX},')
      ..writeln('        pivotY: ${node.transform.pivotY},')
      ..writeln('        perspective: ${node.transform.perspective},')
      ..writeln('      ),')
      ..writeln('      z: ${node.z},')
      ..writeln('      renderOrder: ${node.renderOrder},')
      ..writeln('      focusOrder: ${node.focusOrder},')
      ..writeln('      motion: SceneMotionPreset.${node.motion.name},')
      ..writeln('      bindings: <SceneBinding>{');
    for (final binding in node.bindings) {
      buffer.writeln('        SceneBinding.${binding.name},');
    }
    buffer
      ..writeln('      },')
      ..writeln(
        '      action: ${node.action == null ? 'null' : 'SceneAction.${node.action!.name}'},',
      )
      ..writeln('      properties: <String, String>{');
    for (final entry in node.properties.entries) {
      buffer.writeln(
        '        ${_dartString(entry.key)}: ${_dartString(entry.value)},',
      );
    }
    buffer
      ..writeln('      },')
      ..writeln('    ),');
  }

  buffer
    ..writeln('  ],')
    ..writeln(');')
    ..writeln();
  return buffer.toString();
}

String _variableName(String id) {
  final parts = id.split(RegExp(r'[^A-Za-z0-9]+'))
    ..removeWhere((part) => part.isEmpty);
  if (parts.isEmpty) {
    return 'generatedSceneDocument';
  }
  final first = parts.first;
  final rest = parts
      .skip(1)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}');
  return '${first[0].toLowerCase()}${first.substring(1)}${rest.join()}SceneDocument';
}

String _dartString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$escaped'";
}

String _dartNullableString(String? value) {
  return value == null ? 'null' : _dartString(value);
}

String _colorLiteral(String value) {
  final hex = value.replaceFirst('#', '');
  if (hex.length != 6 && hex.length != 8) {
    throw FormatException('Color must use #RRGGBB or #AARRGGBB: $value');
  }
  final normalized = hex.length == 6 ? 'ff$hex' : hex;
  return 'Color(0x${normalized.toLowerCase()})';
}

void _validateColor(String value) {
  _colorLiteral(value);
}

T _enumValue<T extends Enum>(List<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  throw FormatException('Invalid $field value: $name');
}

Map<String, dynamic> _map(
  Map<String, dynamic> json,
  String key, {
  Map<String, dynamic>? fallback,
}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  return _asMap(value, key);
}

Map<String, dynamic> _asMap(Object? value, String field) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw FormatException('$field must be an object.');
}

List<dynamic> _list(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is List) {
    return value;
  }
  throw FormatException('$key must be a list.');
}

List<String> _stringList(
  Map<String, dynamic> json,
  String key, {
  required List<String> fallback,
}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is! List) {
    throw FormatException('$key must be a list.');
  }
  return [for (final item in value) _asString(item, key)];
}

String _string(Map<String, dynamic> json, String key, {String? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  return _asString(value, key);
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  return _asString(value, key);
}

String _asString(Object? value, String field) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('$field must be a non-empty string.');
}

bool _bool(Map<String, dynamic> json, String key, {required bool fallback}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('$key must be a boolean.');
}

double _double(Map<String, dynamic> json, String key, {double? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('$key must be a number.');
}

int _int(Map<String, dynamic> json, String key, {int? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('$key must be an integer.');
}
