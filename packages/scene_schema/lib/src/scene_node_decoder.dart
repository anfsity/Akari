import 'scene_color_codec.dart';
import 'scene_condition.dart';
import 'scene_document.dart';
import 'scene_json_reader.dart';
import 'scene_layout.dart';
import 'scene_motion.dart';
import 'scene_style.dart';

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

SceneNode decodeSceneNode(JsonMap json, Set<String> nodeIds, int version) {
  final id = getString(json, 'id');
  if (!nodeIds.add(id)) {
    throw FormatException('Duplicate scene node id: $id');
  }

  final rect = _decodeRect(getMap(json, 'rect'), id);
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
    styleToken: findString(json, 'styleToken'),
    primitive: json['primitive'] == null
        ? null
        : getEnumValue(
            ScenePrimitive.values,
            getString(json, 'primitive'),
            'primitive',
          ),
    asset: json['asset'] == null ? null : _decodeAsset(getMap(json, 'asset')),
    transitions: _decodeTransitions(json),
    stateEffects: _decodeStateEffects(json),
    tracks: _decodeTracks(json),
    motionTiming: _decodeMotionTiming(
      getMap(json, 'motionTiming', fallback: const {}),
    ),
    parentId: findString(json, 'parentId'),
    layout: json['layout'] == null
        ? null
        : _decodeLayout(getMap(json, 'layout')),
    sizing: _decodeSizing(getMap(json, 'sizing', fallback: const {})),
    breakpoints: _decodeBreakpoints(json),
    transform: json['transform'] == null
        ? const SceneTransform()
        : _decodeTransform(getMap(json, 'transform')),
    z: getInt(json, 'z', fallback: 0),
    renderOrder: getInt(json, 'renderOrder', fallback: 0),
    focusOrder: getInt(json, 'focusOrder', fallback: 0),
    motion: getEnumValue(
      SceneMotionPreset.values,
      getString(json, 'motion', fallback: SceneMotionPreset.none.name),
      'node.motion',
    ),
    visibleWhen: _decodeCondition(json['visibleWhen'], 'node.visibleWhen'),
    interactive: component.interactive,
    properties: <String, String>{
      for (final entry in getMap(
        json,
        'properties',
        fallback: const {},
      ).entries)
        getNonEmptyKey(entry.key, 'node.properties'): getStringValue(
          entry.value,
          'node.properties.${entry.key}',
        ),
    },
  );
}

List<SceneStateTransition> _decodeTransitions(JsonMap json) {
  final rawTransitions = json['transitions'] == null
      ? const <Object?>[]
      : getList(json, 'transitions');
  return [for (final raw in rawTransitions) _decodeTransition(raw)];
}

SceneStateTransition _decodeTransition(Object? raw) {
  final rule = getMapValue(raw, 'transitions[]');
  final source = _decodeCondition(
    rule['source'] ?? rule['from'],
    'transition.source',
  );
  final target = _decodeCondition(
    rule['target'] ?? rule['to'],
    'transition.target',
  );
  if (source == null || target == null) {
    throw const FormatException(
      'Transitions require source and target conditions.',
    );
  }
  return SceneStateTransition(
    source: source,
    target: target,
    effect: getEnumValue(
      SceneStateEffect.values,
      getString(rule, 'effect'),
      'transition.effect',
    ),
    timing: _decodeMotionTiming(getMap(rule, 'timing', fallback: const {})),
  );
}

Map<ScenePredicate, SceneStateEffect> _decodeStateEffects(JsonMap json) => {
  for (final entry in getMap(json, 'stateEffects', fallback: const {}).entries)
    getEnumValue(
      ScenePredicate.values,
      entry.key,
      'stateEffects.trigger',
    ): getEnumValue(
      SceneStateEffect.values,
      getStringValue(entry.value, 'stateEffects.effect'),
      'stateEffects.effect',
    ),
};

SceneRect _decodeRect(JsonMap json, String id) {
  final rect = SceneRect(
    x: getDouble(json, 'x'),
    y: getDouble(json, 'y'),
    width: getDouble(json, 'width'),
    height: getDouble(json, 'height'),
  );
  if (!rect.isNormalized) {
    throw FormatException('Node $id has a non-normalized rect.');
  }

  return rect;
}

SceneTransform _decodeTransform(JsonMap json) {
  const defaults = SceneTransform();
  return SceneTransform(
    translateX: getDouble(json, 'translateX', fallback: defaults.translateX),
    translateY: getDouble(json, 'translateY', fallback: defaults.translateY),
    scaleX: getDouble(json, 'scaleX', fallback: defaults.scaleX),
    scaleY: getDouble(json, 'scaleY', fallback: defaults.scaleY),
    rotationX: getDouble(json, 'rotationX', fallback: defaults.rotationX),
    rotationY: getDouble(json, 'rotationY', fallback: defaults.rotationY),
    rotationZ: getDouble(json, 'rotationZ', fallback: defaults.rotationZ),
    pivotX: getDouble(json, 'pivotX', fallback: defaults.pivotX),
    pivotY: getDouble(json, 'pivotY', fallback: defaults.pivotY),
    perspective: getDouble(json, 'perspective', fallback: defaults.perspective),
  );
}

// Convert the legacy kind/action vocabulary at the authoring boundary. The
// rest of node decoding consumes one component identity and interactivity flag.
({String id, bool interactive}) _decodeComponent(
  JsonMap json,
  String nodeId,
  int version,
) {
  final field = version == 1 ? 'kind' : 'component';
  final id = getString(json, field);
  if (id.trim().isEmpty) {
    throw FormatException('Node $nodeId has an empty component id.');
  }
  if (version != 1) {
    return (id: id, interactive: getBool(json, 'interactive', fallback: false));
  }
  if (!_legacyComponentIds.contains(id)) {
    throw FormatException('Unknown version 1 node kind: $id');
  }
  final action = findString(json, 'action');
  if (action != null && !_legacyActionIds.contains(action)) {
    throw FormatException('Unknown version 1 node action: $action');
  }
  return (
    id: id,
    interactive: action != null || _legacyInteractiveComponentIds.contains(id),
  );
}

List<SceneMotionTrack> _decodeTracks(JsonMap json) {
  final properties = <SceneMotionProperty>{};
  final rawTracks = json['tracks'] == null
      ? const <Object?>[]
      : getList(json, 'tracks');
  return [for (final raw in rawTracks) _decodeMotionTrack(raw, properties)];
}

SceneMotionTrack _decodeMotionTrack(
  Object? raw,
  Set<SceneMotionProperty> properties,
) {
  final track = getMapValue(raw, 'tracks[]');
  final property = getEnumValue(
    SceneMotionProperty.values,
    getString(track, 'property'),
    'track.property',
  );
  if (!properties.add(property)) {
    throw const FormatException('Only one track per property is allowed.');
  }
  var previous = -1;
  final frames = <SceneKeyframe>[];
  for (final rawFrame in getList(track, 'keyframes')) {
    final frame = getMapValue(rawFrame, 'keyframes[]');
    final time = getInt(frame, 'timeMs');
    final value = getDouble(frame, 'value');
    if (time <= previous ||
        time > maxSceneMotionTimeMs ||
        value.abs() > maxSceneKeyframeMagnitude ||
        (property == SceneMotionProperty.opacity && (value < 0 || value > 1))) {
      throw const FormatException(
        'Keyframes require increasing times in 0..60000 and valid property values.',
      );
    }
    previous = time;
    frames.add(
      SceneKeyframe(
        timeMs: time,
        value: value,
        curve: getEnumValue(
          SceneKeyframeCurve.values,
          getString(frame, 'curve', fallback: 'linear'),
          'keyframe.curve',
        ),
      ),
    );
  }
  if (frames.isEmpty) {
    throw const FormatException('A track requires a keyframe.');
  }
  return SceneMotionTrack(property: property, keyframes: frames);
}

SceneAsset _decodeAsset(JsonMap json) {
  final path = getString(json, 'path');
  validateSceneAssetPath(path);
  return SceneAsset(
    path: path,
    kind: getEnumValue(
      SceneAssetKind.values,
      getString(json, 'kind', fallback: 'image'),
      'asset.kind',
    ),
    fit: getEnumValue(
      SceneAssetFit.values,
      getString(json, 'fit', fallback: 'contain'),
      'asset.fit',
    ),
    tint: json['tint'] == null
        ? null
        : decodeSceneColor(getString(json, 'tint')),
  );
}

SceneMotionTiming _decodeMotionTiming(JsonMap json) {
  final duration = json['durationMs'] == null
      ? null
      : getInt(json, 'durationMs');
  final delay = getInt(json, 'delayMs', fallback: 0);
  if ((duration != null && (duration < 0 || duration > maxSceneMotionTimeMs)) ||
      delay < 0 ||
      delay > maxSceneMotionTimeMs) {
    throw const FormatException(
      'Motion duration and delay must be in 0..60000 ms.',
    );
  }
  SceneCubicBezier? curve;
  if (json['curve'] != null) {
    final values = getList(json, 'curve');
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

SceneLayout _decodeLayout(JsonMap json) => SceneLayout(
  direction: getEnumValue(
    SceneLayoutDirection.values,
    getString(json, 'direction', fallback: 'absolute'),
    'layout.direction',
  ),
  padding: getNonNegative(json, 'padding'),
  gap: getNonNegative(json, 'gap'),
  mainAlignment: getEnumValue(
    SceneMainAlignment.values,
    getString(json, 'mainAlignment', fallback: 'start'),
    'layout.mainAlignment',
  ),
  crossAlignment: getEnumValue(
    SceneCrossAlignment.values,
    getString(json, 'crossAlignment', fallback: 'start'),
    'layout.crossAlignment',
  ),
  clip: getBool(json, 'clip', fallback: false),
  wrap: getBool(json, 'wrap', fallback: false),
);

SceneSizing _decodeSizing(JsonMap json) {
  final width = json['width'] == null ? null : getNonNegative(json, 'width');
  final height = json['height'] == null ? null : getNonNegative(json, 'height');
  if (width == 0 || height == 0) {
    throw const FormatException('Fixed dimensions must be greater than zero.');
  }
  final minWidth = getNonNegative(json, 'minWidth');
  final minHeight = getNonNegative(json, 'minHeight');
  final maxWidth = json['maxWidth'] == null
      ? null
      : getNonNegative(json, 'maxWidth');
  final maxHeight = json['maxHeight'] == null
      ? null
      : getNonNegative(json, 'maxHeight');
  if ((maxWidth != null && (maxWidth == 0 || maxWidth < minWidth)) ||
      (maxHeight != null && (maxHeight == 0 || maxHeight < minHeight))) {
    throw const FormatException(
      'Maximum size must be positive and at least the minimum.',
    );
  }
  return SceneSizing(
    width: width,
    height: height,
    flex: getNonNegative(json, 'flex'),
    minWidth: minWidth,
    minHeight: minHeight,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    widthMode: getEnumValue(
      SceneSizeMode.values,
      getString(json, 'widthMode', fallback: 'proportional'),
      'sizing.widthMode',
    ),
    heightMode: getEnumValue(
      SceneSizeMode.values,
      getString(json, 'heightMode', fallback: 'proportional'),
      'sizing.heightMode',
    ),
  );
}

List<SceneBreakpoint> _decodeBreakpoints(JsonMap json) {
  final widths = <double>{};
  final rawBreakpoints = json['breakpoints'] == null
      ? const <Object?>[]
      : getList(json, 'breakpoints');
  return [
    for (final value in rawBreakpoints) _decodeBreakpoint(value, json, widths),
  ];
}

SceneBreakpoint _decodeBreakpoint(
  Object? value,
  JsonMap nodeJson,
  Set<double> widths,
) {
  final rule = getMapValue(value, 'breakpoints[]');
  final width = getNonNegative(rule, 'minWidth');
  if (width > 16384 || !widths.add(width)) {
    throw const FormatException(
      'Breakpoints require unique widths in 0..16384.',
    );
  }
  if (rule['layout'] != null && nodeJson['layout'] == null) {
    throw const FormatException('Only frames can override layout.');
  }
  if (rule['layout'] == null && rule['sizing'] == null) {
    throw const FormatException('A breakpoint must override layout or sizing.');
  }
  return SceneBreakpoint(
    minWidth: width,
    layout: rule['layout'] == null
        ? null
        : _decodeLayout(getMap(rule, 'layout')),
    sizing: rule['sizing'] == null
        ? null
        : _decodeSizing(getMap(rule, 'sizing')),
  );
}

SceneCondition? _decodeCondition(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return ScenePredicateCondition(
      getEnumValue(ScenePredicate.values, value, field),
    );
  }
  final map = getMapValue(value, field);
  if (map.length != 1) {
    throw FormatException('$field must use exactly one of all, any, or not.');
  }
  final entry = map.entries.single;
  return switch (entry.key) {
    'all' => SceneAll(_decodeConditionList(entry.value, '$field.all')),
    'any' => SceneAny(_decodeConditionList(entry.value, '$field.any')),
    'not' => SceneNot(_decodeRequiredCondition(entry.value, '$field.not')),
    _ => throw FormatException('Invalid $field operator: ${entry.key}'),
  };
}

SceneCondition _decodeRequiredCondition(Object? value, String field) =>
    _decodeCondition(value, field) ??
    (throw FormatException('$field requires a condition.'));

List<SceneCondition> _decodeConditionList(Object? value, String field) {
  if (value is! List<Object?> || value.isEmpty) {
    throw FormatException('$field must be a non-empty list.');
  }
  return [for (final item in value) _decodeRequiredCondition(item, field)];
}
