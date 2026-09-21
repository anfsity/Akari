import 'dart:convert';

import 'scene_document.dart';

/// Decodes a scene document from its JSON authoring form.
SceneDocument decodeSceneDocument(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Scene document root must be a JSON object.');
  }
  return decodeSceneDocumentMap(decoded);
}

/// Decodes a scene document from an already-parsed JSON map.
SceneDocument decodeSceneDocumentMap(Map<String, dynamic> json) {
  final version = _int(json, 'version');
  if (version != 1) {
    throw FormatException('Unsupported scene version: $version');
  }

  final nodesJson = _list(json, 'nodes');
  final nodeIds = <String>{};
  final nodes = <SceneNode>[
    for (final rawNode in nodesJson)
      _decodeNode(_asMap(rawNode, 'nodes[]'), nodeIds),
  ];
  if (nodes.isEmpty) {
    throw const FormatException(
      'Scene document must contain at least one node.',
    );
  }

  final canvasJson = _map(json, 'canvas');
  return SceneDocument(
    id: _string(json, 'id'),
    version: version,
    canvas: SceneCanvas(
      fit: _enumValue(
        SceneCanvasFit.values,
        _string(canvasJson, 'fit'),
        'canvas.fit',
      ),
      useSafeArea: _bool(canvasJson, 'useSafeArea', fallback: true),
    ),
    background: _decodeBackground(_map(json, 'background')),
    nodes: nodes,
  );
}

/// Encodes a scene document into its JSON authoring form.
String encodeSceneDocument(SceneDocument document) {
  return const JsonEncoder.withIndent('  ').convert(sceneDocumentToMap(document));
}

/// Encodes a scene document into a JSON-ready map.
Map<String, dynamic> sceneDocumentToMap(SceneDocument document) {
  return {
    'id': document.id,
    'version': document.version,
    'canvas': {
      'fit': document.canvas.fit.name,
      'useSafeArea': document.canvas.useSafeArea,
    },
    'background': _encodeBackground(document.background),
    'nodes': [for (final node in document.nodes) _encodeNode(node)],
  };
}

SceneBackground _decodeBackground(Map<String, dynamic> json) {
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
  final scrimOpacity = _double(json, 'scrimOpacity', fallback: 0.35);
  if (scrimOpacity < 0 || scrimOpacity > 1) {
    throw FormatException('background.scrimOpacity must be in [0, 1].');
  }
  final blurSigma = _double(json, 'blurSigma', fallback: 0);
  if (blurSigma < 0) {
    throw FormatException('background.blurSigma must be >= 0.');
  }
  return SceneBackground(
    kind: kind,
    asset: asset,
    color: _decodeColor(_string(json, 'color', fallback: '#0d151a')),
    scrimOpacity: scrimOpacity,
    blurSigma: blurSigma,
    rendererId: _nullableString(json, 'rendererId'),
  );
}

Map<String, dynamic> _encodeBackground(SceneBackground background) {
  return {
    'kind': background.kind.name,
    if (background.asset != null) 'asset': background.asset,
    'color': _encodeColor(background.color),
    'scrimOpacity': background.scrimOpacity,
    'blurSigma': background.blurSigma,
    if (background.rendererId != null) 'rendererId': background.rendererId,
  };
}

SceneNode _decodeNode(Map<String, dynamic> json, Set<String> nodeIds) {
  final id = _string(json, 'id');
  if (!nodeIds.add(id)) {
    throw FormatException('Duplicate scene node id: $id');
  }

  final rectJson = _map(json, 'rect');
  final rect = SceneRect(
    x: _double(rectJson, 'x'),
    y: _double(rectJson, 'y'),
    width: _double(rectJson, 'width'),
    height: _double(rectJson, 'height'),
  );
  if (!rect.isNormalized) {
    throw FormatException('Node $id has a non-normalized rect.');
  }

  final transformJson = _map(json, 'transform', fallback: const {});
  final actionName = _nullableString(json, 'action');

  return SceneNode(
    id: id,
    kind: _enumValue(SceneNodeKind.values, _string(json, 'kind'), 'node.kind'),
    rect: rect,
    transform: SceneTransform(
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
    ),
    z: _int(json, 'z', fallback: 0),
    renderOrder: _int(json, 'renderOrder', fallback: 0),
    focusOrder: _int(json, 'focusOrder', fallback: 0),
    motion: _enumValue(
      SceneMotionPreset.values,
      _string(json, 'motion', fallback: 'none'),
      'node.motion',
    ),
    visibleWhen: _decodeCondition(json['visibleWhen'], 'node.visibleWhen'),
    action: actionName == null
        ? null
        : _enumValue(SceneAction.values, actionName, 'node.action'),
    properties: <String, String>{
      for (final entry in _map(json, 'properties', fallback: const {}).entries)
        entry.key: _asString(entry.value, 'node.properties.${entry.key}'),
    },
  );
}

Map<String, dynamic> _encodeNode(SceneNode node) {
  return {
    'id': node.id,
    'kind': node.kind.name,
    'rect': {
      'x': node.rect.x,
      'y': node.rect.y,
      'width': node.rect.width,
      'height': node.rect.height,
    },
    if (!node.transform.isIdentity) 'transform': _encodeTransform(node.transform),
    if (node.z != 0) 'z': node.z,
    if (node.renderOrder != 0) 'renderOrder': node.renderOrder,
    if (node.focusOrder != 0) 'focusOrder': node.focusOrder,
    if (node.motion != SceneMotionPreset.none) 'motion': node.motion.name,
    if (node.visibleWhen != null)
      'visibleWhen': _encodeCondition(node.visibleWhen!),
    if (node.action != null) 'action': node.action!.name,
    if (node.properties.isNotEmpty) 'properties': node.properties,
  };
}

Map<String, dynamic> _encodeTransform(SceneTransform transform) {
  return {
    'translateX': transform.translateX,
    'translateY': transform.translateY,
    'scaleX': transform.scaleX,
    'scaleY': transform.scaleY,
    'rotationX': transform.rotationX,
    'rotationY': transform.rotationY,
    'rotationZ': transform.rotationZ,
    'pivotX': transform.pivotX,
    'pivotY': transform.pivotY,
    'perspective': transform.perspective,
  };
}

SceneCondition? _decodeCondition(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return ScenePredicateCondition(
      _enumValue(ScenePredicate.values, value, field),
    );
  }
  final map = _asMap(value, field);
  if (map.length != 1) {
    throw FormatException('$field must use exactly one of all, any, or not.');
  }
  final entry = map.entries.single;
  return switch (entry.key) {
    'all' => SceneAll(_decodeConditionList(entry.value, '$field.all')),
    'any' => SceneAny(_decodeConditionList(entry.value, '$field.any')),
    'not' => SceneNot(_decodeCondition(entry.value, '$field.not')!),
    _ => throw FormatException('Invalid $field operator: ${entry.key}'),
  };
}

List<SceneCondition> _decodeConditionList(Object? value, String field) {
  if (value is! List || value.isEmpty) {
    throw FormatException('$field must be a non-empty list.');
  }
  return [
    for (final item in value) _decodeCondition(item, field)!,
  ];
}

Object _encodeCondition(SceneCondition condition) {
  return switch (condition) {
    ScenePredicateCondition(:final predicate) => predicate.name,
    SceneAll(:final conditions) => {
      'all': [for (final child in conditions) _encodeCondition(child)],
    },
    SceneAny(:final conditions) => {
      'any': [for (final child in conditions) _encodeCondition(child)],
    },
    SceneNot(:final condition) => {'not': _encodeCondition(condition)},
  };
}

int _decodeColor(String value) {
  final hex = value.startsWith('#') ? value.substring(1) : value;
  if (hex.length != 6 && hex.length != 8) {
    throw FormatException('Color must use #RRGGBB or #AARRGGBB: $value');
  }
  final normalized = hex.length == 6 ? 'ff$hex' : hex;
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) {
    throw FormatException('Color must be hexadecimal: $value');
  }
  return parsed;
}

String _encodeColor(int value) {
  final hex = value.toRadixString(16).padLeft(8, '0');
  if (hex.startsWith('ff')) {
    return '#${hex.substring(2)}';
  }
  return '#$hex';
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
