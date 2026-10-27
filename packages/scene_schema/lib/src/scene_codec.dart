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
  if (version < 1 || version > currentSceneVersion) {
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
  _validateHierarchy(nodes);
  final styles = {
    for (final entry in _getMap(
      decoded,
      'styleTokens',
      fallback: const {},
    ).entries)
      entry.key: _decodeStyle(
        _getMapValue(entry.value, 'styleTokens.${entry.key}'),
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
    id: _getString(decoded, 'id'),
    version: currentSceneVersion,
    canvas: _decodeCanvas(_getMap(decoded, 'canvas')),
    background: _decodeBackground(_getMap(decoded, 'background')),
    nodes: nodes,
    styleTokens: styles,
    guides: [
      for (final value
          in decoded['guides'] == null ? const [] : _getList(decoded, 'guides'))
        _decodeGuide(_getMapValue(value, 'guides[]')),
    ],
    themeProperties: {
      for (final entry in _getMap(
        decoded,
        'themeProperties',
        fallback: const {},
      ).entries)
        entry.key: _getStringValue(entry.value, 'themeProperties.${entry.key}'),
    },
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
  return const JsonEncoder.withIndent('  ').convert(_encodeDocument(document));
}

/// Encodes a single scene node into its formatted JSON authoring form.
String encodeSceneNode(SceneNode node) {
  return const JsonEncoder.withIndent('  ').convert(_encodeNode(node));
}

Map<String, dynamic> _encodeDocument(SceneDocument document) {
  return {
    'id': document.id,
    'version': document.version,
    if (document.guides.isNotEmpty)
      'guides': [
        for (final guide in document.guides)
          {'axis': guide.axis.name, 'position': guide.position},
      ],
    if (document.styleTokens.isNotEmpty)
      'styleTokens': {
        for (final entry in document.styleTokens.entries)
          entry.key: _encodeStyle(entry.value),
      },
    if (document.themeProperties.isNotEmpty)
      'themeProperties': document.themeProperties,
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
  final parameters = _getMap(json, 'parameters', fallback: const {});
  return SceneBackground(
    kind: kind,
    asset: asset,
    color: json['color'] == null
        ? defaults.color
        : decodeSceneColor(_getString(json, 'color')),
    scrimOpacity: scrimOpacity,
    blurSigma: blurSigma,
    rendererId: _findString(json, 'rendererId'),
    parameters: {
      for (final key in parameters.keys) key: _getDouble(parameters, key),
    },
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
    if (background.parameters.isNotEmpty) 'parameters': background.parameters,
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
  if ([
        'layout',
        'asset',
        'primitive',
      ].where((key) => json[key] != null).length >
      1) {
    throw const FormatException(
      'A node can contain one of layout, asset, or primitive.',
    );
  }
  return SceneNode(
    id: id,
    componentId: component.id,
    rect: rect,
    styleToken: _findString(json, 'styleToken'),
    primitive: json['primitive'] == null
        ? null
        : _getEnumValue(
            ScenePrimitive.values,
            _getString(json, 'primitive'),
            'primitive',
          ),
    asset: json['asset'] == null ? null : _decodeAsset(_getMap(json, 'asset')),
    stateEffects: {
      for (final entry in _getMap(
        json,
        'stateEffects',
        fallback: const {},
      ).entries)
        _getEnumValue(
          ScenePredicate.values,
          entry.key,
          'stateEffects.trigger',
        ): _getEnumValue(
          SceneStateEffect.values,
          _getStringValue(entry.value, 'stateEffects.effect'),
          'stateEffects.effect',
        ),
    },
    motionTiming: _decodeMotionTiming(
      _getMap(json, 'motionTiming', fallback: const {}),
    ),
    parentId: _findString(json, 'parentId'),
    layout: json['layout'] == null
        ? null
        : _decodeLayout(_getMap(json, 'layout')),
    sizing: _decodeSizing(_getMap(json, 'sizing', fallback: const {})),
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
    if (node.styleToken != null) 'styleToken': node.styleToken,
    if (node.primitive != null) 'primitive': node.primitive!.name,
    if (node.asset case final asset?)
      'asset': {
        'path': asset.path,
        'kind': asset.kind.name,
        'fit': asset.fit.name,
        if (asset.tint != null) 'tint': encodeSceneColor(asset.tint!),
      },
    if (node.parentId != null) 'parentId': node.parentId,
    if (node.layout case final layout?)
      'layout': {
        'direction': layout.direction.name,
        'padding': layout.padding,
        'gap': layout.gap,
        'mainAlignment': layout.mainAlignment.name,
        'crossAlignment': layout.crossAlignment.name,
        'clip': layout.clip,
      },
    if (node.sizing.width != null ||
        node.sizing.height != null ||
        node.sizing.flex != 0)
      'sizing': {
        if (node.sizing.width != null) 'width': node.sizing.width,
        if (node.sizing.height != null) 'height': node.sizing.height,
        if (node.sizing.flex != 0) 'flex': node.sizing.flex,
      },
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
    if (node.stateEffects.isNotEmpty)
      'stateEffects': {
        for (final entry in node.stateEffects.entries)
          entry.key.name: entry.value.name,
      },
    if (!node.motionTiming.isDefault)
      'motionTiming': {
        if (node.motionTiming.durationMs != null)
          'durationMs': node.motionTiming.durationMs,
        'delayMs': node.motionTiming.delayMs,
        if (node.motionTiming.curve case final curve?)
          'curve': [curve.x1, curve.y1, curve.x2, curve.y2],
      },
    if (node.visibleWhen != null)
      'visibleWhen': _encodeCondition(node.visibleWhen!),
    if (node.interactive) 'interactive': true,
    if (node.properties.isNotEmpty) 'properties': node.properties,
  };
}

SceneAsset _decodeAsset(Map<String, dynamic> json) {
  final path = _getString(json, 'path');
  if (path.contains('..') ||
      path.contains(r'\') ||
      path.endsWith('/') ||
      (!path.startsWith('assets/') && !path.startsWith('packages/'))) {
    throw FormatException('Invalid scene asset path: $path');
  }
  return SceneAsset(
    path: path,
    kind: _getEnumValue(
      SceneAssetKind.values,
      _getString(json, 'kind', fallback: 'image'),
      'asset.kind',
    ),
    fit: _getEnumValue(
      SceneAssetFit.values,
      _getString(json, 'fit', fallback: 'contain'),
      'asset.fit',
    ),
    tint: json['tint'] == null
        ? null
        : decodeSceneColor(_getString(json, 'tint')),
  );
}

SceneGuide _decodeGuide(Map<String, dynamic> json) {
  final position = _getDouble(json, 'position');
  if (position < 0 || position > 1) {
    throw const FormatException('Guide position must be in [0, 1].');
  }
  return SceneGuide(
    axis: _getEnumValue(
      SceneGuideAxis.values,
      _getString(json, 'axis'),
      'guide.axis',
    ),
    position: position,
  );
}

SceneMotionTiming _decodeMotionTiming(Map<String, dynamic> json) {
  final duration = json['durationMs'] == null
      ? null
      : _getInt(json, 'durationMs');
  final delay = _getInt(json, 'delayMs', fallback: 0);
  if ((duration != null && (duration < 0 || duration > 60000)) ||
      delay < 0 ||
      delay > 60000) {
    throw const FormatException(
      'Motion duration and delay must be in 0..60000 ms.',
    );
  }
  SceneCubicBezier? curve;
  if (json['curve'] != null) {
    final values = _getList(json, 'curve');
    if (values.length != 4 ||
        values.any(
          (value) => value is! num || !value.isFinite || value < 0 || value > 1,
        )) {
      throw const FormatException(
        'Motion curve must contain four numbers in [0, 1].',
      );
    }
    curve = SceneCubicBezier(
      (values[0] as num).toDouble(),
      (values[1] as num).toDouble(),
      (values[2] as num).toDouble(),
      (values[3] as num).toDouble(),
    );
  }
  return SceneMotionTiming(durationMs: duration, delayMs: delay, curve: curve);
}

SceneStyle _decodeStyle(Map<String, dynamic> json) {
  const defaults = SceneStyle();
  int color(String key, int fallback) =>
      json[key] == null ? fallback : decodeSceneColor(_getString(json, key));
  final opacity = _getDouble(json, 'opacity', fallback: 1);
  if (opacity < 0 || opacity > 1) {
    throw const FormatException('Style opacity must be in [0, 1].');
  }
  return SceneStyle(
    fill: color('fill', defaults.fill),
    gradientEnd: json['gradientEnd'] == null ? null : color('gradientEnd', 0),
    gradientAngle: _getDouble(
      json,
      'gradientAngle',
      fallback: defaults.gradientAngle,
    ),
    border: color('border', defaults.border),
    borderWidth: _getNonNegative(json, 'borderWidth'),
    radius: _getNonNegative(json, 'radius'),
    shadow: color('shadow', defaults.shadow),
    shadowBlur: _getNonNegative(json, 'shadowBlur'),
    shadowY: _getDouble(json, 'shadowY', fallback: defaults.shadowY),
    backgroundBlur: _getNonNegative(json, 'backgroundBlur'),
    textColor: json['textColor'] == null ? null : color('textColor', 0),
    fontSize: _getNonNegative(json, 'fontSize'),
    opacity: opacity,
  );
}

Map<String, dynamic> _encodeStyle(SceneStyle style) => {
  'fill': encodeSceneColor(style.fill),
  if (style.gradientEnd != null)
    'gradientEnd': encodeSceneColor(style.gradientEnd!),
  'gradientAngle': style.gradientAngle,
  'border': encodeSceneColor(style.border),
  'borderWidth': style.borderWidth,
  'radius': style.radius,
  'shadow': encodeSceneColor(style.shadow),
  'shadowBlur': style.shadowBlur,
  'shadowY': style.shadowY,
  'backgroundBlur': style.backgroundBlur,
  if (style.textColor != null) 'textColor': encodeSceneColor(style.textColor!),
  'fontSize': style.fontSize,
  'opacity': style.opacity,
};

SceneLayout _decodeLayout(Map<String, dynamic> json) => SceneLayout(
  direction: _getEnumValue(
    SceneLayoutDirection.values,
    _getString(json, 'direction', fallback: 'absolute'),
    'layout.direction',
  ),
  padding: _getNonNegative(json, 'padding'),
  gap: _getNonNegative(json, 'gap'),
  mainAlignment: _getEnumValue(
    SceneMainAlignment.values,
    _getString(json, 'mainAlignment', fallback: 'start'),
    'layout.mainAlignment',
  ),
  crossAlignment: _getEnumValue(
    SceneCrossAlignment.values,
    _getString(json, 'crossAlignment', fallback: 'start'),
    'layout.crossAlignment',
  ),
  clip: _getBool(json, 'clip', fallback: false),
);

SceneSizing _decodeSizing(Map<String, dynamic> json) {
  final width = json['width'] == null ? null : _getNonNegative(json, 'width');
  final height = json['height'] == null
      ? null
      : _getNonNegative(json, 'height');
  if (width == 0 || height == 0) {
    throw const FormatException('Fixed dimensions must be greater than zero.');
  }
  return SceneSizing(
    width: width,
    height: height,
    flex: _getNonNegative(json, 'flex'),
  );
}

double _getNonNegative(Map<String, dynamic> json, String key) {
  final value = _getDouble(json, key, fallback: 0);
  if (value < 0) {
    throw FormatException('$key must be finite and >= 0.');
  }
  return value;
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
  if (value is num && value.isFinite) {
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
