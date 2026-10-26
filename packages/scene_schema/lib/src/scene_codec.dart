import 'dart:convert';

import 'scene_document.dart';

const _legacyComponentIds = <String>{
  'background',
  'glassPanel',
  'avatar',
  'accountName',
  'accountPicker',
  'sessionPicker',
  'credentialField',
  'primaryAction',
  'secondaryAction',
  'powerActions',
  'dateTime',
  'status',
  'decoration',
};

const _legacyInteractiveComponentIds = <String>{
  'accountPicker',
  'sessionPicker',
  'credentialField',
  'primaryAction',
  'secondaryAction',
  'powerActions',
};

const _legacyActionIds = <String>{
  'selectUser',
  'selectSession',
  'beginAuthentication',
  'respondToPrompt',
  'cancelAuthentication',
  'requestPowerAction',
  'retryAuthentication',
  'retryPrompt',
  'reconnectService',
  'retrySessionCatalog',
};

/// Decodes a scene document from its JSON authoring form.
///
/// Tooling and code generation share this boundary for shape, enum, layout,
/// and asset-path checks. Production consumes the resulting generated Dart
/// instead of parsing JSON during login.
SceneDocument decodeSceneDocument(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Scene document root must be a JSON object.');
  }
  final version = _getInt(decoded, 'version');
  if (version != 1 && version != currentSceneVersion) {
    throw FormatException('Unsupported scene version: $version');
  }

  final nodeIds = <String>{};
  final nodes = <SceneNode>[
    for (final rawNode in _getList(decoded, 'nodes'))
      _decodeNode(_getMapValue(rawNode, 'nodes[]'), nodeIds, version),
  ];
  if (nodes.isEmpty) {
    throw const FormatException(
      'Scene document must contain at least one node.',
    );
  }

  return SceneDocument(
    id: _getString(decoded, 'id'),
    version: currentSceneVersion,
    canvas: _decodeCanvas(_getMap(decoded, 'canvas')),
    background: _decodeBackground(_getMap(decoded, 'background')),
    nodes: nodes,
  );
}

SceneCanvas _decodeCanvas(Map<String, dynamic> json) {
  const defaults = SceneCanvas();
  final referenceWidth = _getInt(
    json,
    'referenceWidth',
    fallback: defaults.referenceWidth,
  );
  final referenceHeight = _getInt(
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
    fit: _getEnumValue(
      SceneCanvasFit.values,
      _getString(json, 'fit'),
      'canvas.fit',
    ),
    useSafeArea: _getBool(json, 'useSafeArea', fallback: defaults.useSafeArea),
    referenceWidth: referenceWidth,
    referenceHeight: referenceHeight,
  );
}

/// Encodes a scene document into its JSON authoring form.
String encodeSceneDocument(SceneDocument document) {
  return const JsonEncoder.withIndent('  ')
      .convert(_encodeDocument(document));
}

/// Encodes a single scene node into its formatted JSON authoring form.
String encodeSceneNode(SceneNode node) {
  return const JsonEncoder.withIndent('  ').convert(_encodeNode(node));
}

Map<String, dynamic> _encodeDocument(SceneDocument document) {
  return {
    'id': document.id,
    'version': document.version,
    'canvas': {
      'fit': document.canvas.fit.name,
      'useSafeArea': document.canvas.useSafeArea,
      'referenceWidth': document.canvas.referenceWidth,
      'referenceHeight': document.canvas.referenceHeight,
    },
    'background': _encodeBackground(document.background),
    'nodes': [for (final node in document.nodes) _encodeNode(node)],
  };
}

SceneBackground _decodeBackground(Map<String, dynamic> json) {
  const defaults = SceneBackground(kind: SceneBackgroundKind.solid);
  final kind = _getEnumValue(
    SceneBackgroundKind.values,
    _getString(json, 'kind'),
    'background.kind',
  );
  final asset = _findString(json, 'asset');
  if (asset != null &&
      (asset.contains('..') ||
          (!asset.startsWith('assets/') &&
              !asset.startsWith('packages/') &&
              kind == SceneBackgroundKind.image))) {
    throw FormatException('Invalid background asset path: $asset');
  }
  final scrimOpacity = _getDouble(
    json,
    'scrimOpacity',
    fallback: defaults.scrimOpacity,
  );
  if (scrimOpacity < 0 || scrimOpacity > 1) {
    throw FormatException('background.scrimOpacity must be in [0, 1].');
  }
  final blurSigma = _getDouble(json, 'blurSigma', fallback: defaults.blurSigma);
  if (blurSigma < 0) {
    throw FormatException('background.blurSigma must be >= 0.');
  }
  return SceneBackground(
    kind: kind,
    asset: asset,
    color: json['color'] == null
        ? defaults.color
        : decodeSceneColor(_getString(json, 'color')),
    scrimOpacity: scrimOpacity,
    blurSigma: blurSigma,
    rendererId: _findString(json, 'rendererId'),
  );
}

Map<String, dynamic> _encodeBackground(SceneBackground background) {
  return {
    'kind': background.kind.name,
    if (background.asset != null) 'asset': background.asset,
    'color': encodeSceneColor(background.color),
    'scrimOpacity': background.scrimOpacity,
    'blurSigma': background.blurSigma,
    if (background.rendererId != null) 'rendererId': background.rendererId,
  };
}

SceneNode _decodeNode(
  Map<String, dynamic> json,
  Set<String> nodeIds,
  int version,
) {
  final id = _getString(json, 'id');
  if (!nodeIds.add(id)) {
    throw FormatException('Duplicate scene node id: $id');
  }

  final rect = _decodeRect(_getMap(json, 'rect'), id);
  final component = _decodeComponent(json, id, version);
  return SceneNode(
    id: id,
    componentId: component.id,
    rect: rect,
    transform: json['transform'] == null
        ? const SceneTransform()
        : _decodeTransform(_getMap(json, 'transform')),
    z: _getInt(json, 'z', fallback: 0),
    renderOrder: _getInt(json, 'renderOrder', fallback: 0),
    focusOrder: _getInt(json, 'focusOrder', fallback: 0),
    motion: _getEnumValue(
      SceneMotionPreset.values,
      _getString(json, 'motion', fallback: SceneMotionPreset.none.name),
      'node.motion',
    ),
    visibleWhen: _decodeCondition(json['visibleWhen'], 'node.visibleWhen'),
    interactive: component.interactive,
    properties: <String, String>{
      for (final entry in _getMap(
        json,
        'properties',
        fallback: const {},
      ).entries)
        entry.key: _getStringValue(entry.value, 'node.properties.${entry.key}'),
    },
  );
}

SceneRect _decodeRect(Map<String, dynamic> json, String id) {
  final rect = SceneRect(
    x: _getDouble(json, 'x'),
    y: _getDouble(json, 'y'),
    width: _getDouble(json, 'width'),
    height: _getDouble(json, 'height'),
  );
  if (!rect.isNormalized) {
    throw FormatException('Node $id has a non-normalized rect.');
  }

  return rect;
}

SceneTransform _decodeTransform(Map<String, dynamic> json) {
  const defaults = SceneTransform();
  return SceneTransform(
    translateX: _getDouble(json, 'translateX', fallback: defaults.translateX),
    translateY: _getDouble(json, 'translateY', fallback: defaults.translateY),
    scaleX: _getDouble(json, 'scaleX', fallback: defaults.scaleX),
    scaleY: _getDouble(json, 'scaleY', fallback: defaults.scaleY),
    rotationX: _getDouble(json, 'rotationX', fallback: defaults.rotationX),
    rotationY: _getDouble(json, 'rotationY', fallback: defaults.rotationY),
    rotationZ: _getDouble(json, 'rotationZ', fallback: defaults.rotationZ),
    pivotX: _getDouble(json, 'pivotX', fallback: defaults.pivotX),
    pivotY: _getDouble(json, 'pivotY', fallback: defaults.pivotY),
    perspective: _getDouble(
      json,
      'perspective',
      fallback: defaults.perspective,
    ),
  );
}

// Convert the legacy kind/action vocabulary at the authoring boundary. The
// rest of node decoding consumes one component identity and interactivity flag.
({String id, bool interactive}) _decodeComponent(
  Map<String, dynamic> json,
  String nodeId,
  int version,
) {
  final field = version == 1 ? 'kind' : 'component';
  final id = _getString(json, field);
  if (id.trim().isEmpty) {
    throw FormatException('Node $nodeId has an empty component id.');
  }
  if (version != 1) {
    return (
      id: id,
      interactive: _getBool(json, 'interactive', fallback: false),
    );
  }
  if (!_legacyComponentIds.contains(id)) {
    throw FormatException('Unknown version 1 node kind: $id');
  }
  final action = _findString(json, 'action');
  if (action != null && !_legacyActionIds.contains(action)) {
    throw FormatException('Unknown version 1 node action: $action');
  }
  return (
    id: id,
    interactive: action != null || _legacyInteractiveComponentIds.contains(id),
  );
}

Map<String, dynamic> _encodeNode(SceneNode node) {
  return {
    'id': node.id,
    'component': node.componentId,
    'rect': {
      'x': node.rect.x,
      'y': node.rect.y,
      'width': node.rect.width,
      'height': node.rect.height,
    },
    if (!node.transform.isDefault)
      'transform': _encodeTransform(node.transform),
    if (node.z != 0) 'z': node.z,
    if (node.renderOrder != 0) 'renderOrder': node.renderOrder,
    if (node.focusOrder != 0) 'focusOrder': node.focusOrder,
    if (node.motion != SceneMotionPreset.none) 'motion': node.motion.name,
    if (node.visibleWhen != null)
      'visibleWhen': _encodeCondition(node.visibleWhen!),
    if (node.interactive) 'interactive': true,
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
      _getEnumValue(ScenePredicate.values, value, field),
    );
  }
  final map = _getMapValue(value, field);
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
  return [for (final item in value) _decodeCondition(item, field)!];
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

/// Parses a `#RRGGBB` or `#AARRGGBB` scene color into a 32-bit ARGB value.
int decodeSceneColor(String value) {
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

/// Formats a 32-bit ARGB value as a `#RRGGBB` or `#AARRGGBB` scene color.
String encodeSceneColor(int value) {
  final hex = value.toRadixString(16).padLeft(8, '0');
  if (hex.startsWith('ff')) {
    return '#${hex.substring(2)}';
  }
  return '#$hex';
}

T _getEnumValue<T extends Enum>(List<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  throw FormatException('Invalid $field value: $name');
}

Map<String, dynamic> _getMap(
  Map<String, dynamic> json,
  String key, {
  Map<String, dynamic>? fallback,
}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  return _getMapValue(value, key);
}

Map<String, dynamic> _getMapValue(Object? value, String field) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw FormatException('$field must be an object.');
}

List<dynamic> _getList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is List) {
    return value;
  }
  throw FormatException('$key must be a list.');
}

String _getString(Map<String, dynamic> json, String key, {String? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  return _getStringValue(value, key);
}

String? _findString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  return _getStringValue(value, key);
}

String _getStringValue(Object? value, String field) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('$field must be a non-empty string.');
}

bool _getBool(Map<String, dynamic> json, String key, {required bool fallback}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('$key must be a boolean.');
}

double _getDouble(Map<String, dynamic> json, String key, {double? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('$key must be a number.');
}

int _getInt(Map<String, dynamic> json, String key, {int? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) {
    return fallback;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('$key must be an integer.');
}
