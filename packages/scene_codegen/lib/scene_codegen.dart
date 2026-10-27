import 'package:scene_schema/scene_schema.dart';

String generateScene(String input) {
  return generateSceneFromDocument(decodeSceneDocument(input));
}

String generateSceneFromDocument(SceneDocument document) {
  // A getter creates a fresh document after hot reload. A cached top-level
  // final would keep the old scene even after regenerated code is loaded.
  return '''// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated from ${document.id}.scene.json.
import 'package:scene/scene.dart';

SceneDocument get ${getSceneDocumentVariableName(document.id)} => SceneDocument(
  id: ${encodeDartString(document.id)},
  version: ${document.version},
  styleTokens: <String, SceneStyle>{
${document.styleTokens.entries.map((entry) => '    ${encodeDartString(entry.key)}: ${_encodeStyle(entry.value)},\n').join()}  },
  themeProperties: <String, String>{
${document.themeProperties.entries.map((entry) => '    ${encodeDartString(entry.key)}: ${encodeDartString(entry.value)},\n').join()}  },
  canvas: const SceneCanvas(
    fit: SceneCanvasFit.${document.canvas.fit.name},
    useSafeArea: ${document.canvas.useSafeArea},
    referenceWidth: ${document.canvas.referenceWidth},
    referenceHeight: ${document.canvas.referenceHeight},
  ),
  background: SceneBackground(
    kind: SceneBackgroundKind.${document.background.kind.name},
    asset: ${_encodeDartNullableString(document.background.asset)},
    color: ${_encodeColorLiteral(document.background.color)},
    scrimOpacity: ${document.background.scrimOpacity},
    blurSigma: ${document.background.blurSigma},
    rendererId: ${_encodeDartNullableString(document.background.rendererId)},
    parameters: <String, double>{
${document.background.parameters.entries.map((entry) => '      ${encodeDartString(entry.key)}: ${entry.value},\n').join()}    },
  ),
  nodes: <SceneNode>[
${document.nodes.map(generateSceneNode).join()}  ],
);

''';
}

String generateSceneNode(SceneNode node) {
  final properties = [
    for (final entry in node.properties.entries)
      '        ${encodeDartString(entry.key)}: ${encodeDartString(entry.value)},\n',
  ].join();
  return '''    SceneNode(
      id: ${encodeDartString(node.id)},
      componentId: ${encodeDartString(node.componentId)},
      parentId: ${_encodeDartNullableString(node.parentId)},
      styleToken: ${_encodeDartNullableString(node.styleToken)},
      ${node.layout == null ? '' : '''layout: const SceneLayout(
        direction: SceneLayoutDirection.${node.layout!.direction.name},
        padding: ${node.layout!.padding},
        gap: ${node.layout!.gap},
        mainAlignment: SceneMainAlignment.${node.layout!.mainAlignment.name},
        crossAlignment: SceneCrossAlignment.${node.layout!.crossAlignment.name},
        clip: ${node.layout!.clip},
      ),'''}
      sizing: const SceneSizing(
        width: ${node.sizing.width}, height: ${node.sizing.height}, flex: ${node.sizing.flex},
      ),
      rect: const SceneRect(
        x: ${node.rect.x},
        y: ${node.rect.y},
        width: ${node.rect.width},
        height: ${node.rect.height},
      ),
      transform: const SceneTransform(
        translateX: ${node.transform.translateX},
        translateY: ${node.transform.translateY},
        scaleX: ${node.transform.scaleX},
        scaleY: ${node.transform.scaleY},
        rotationX: ${node.transform.rotationX},
        rotationY: ${node.transform.rotationY},
        rotationZ: ${node.transform.rotationZ},
        pivotX: ${node.transform.pivotX},
        pivotY: ${node.transform.pivotY},
        perspective: ${node.transform.perspective},
      ),
      z: ${node.z},
      renderOrder: ${node.renderOrder},
      focusOrder: ${node.focusOrder},
      motion: SceneMotionPreset.${node.motion.name},
      stateEffects: <ScenePredicate, SceneStateEffect>{
${node.stateEffects.entries.map((entry) => '        ScenePredicate.${entry.key.name}: SceneStateEffect.${entry.value.name},\n').join()}      },
      motionTiming: const SceneMotionTiming(durationMs: ${node.motionTiming.durationMs}, delayMs: ${node.motionTiming.delayMs},
        curve: ${node.motionTiming.curve == null ? 'null' : 'SceneCubicBezier(${node.motionTiming.curve!.x1}, ${node.motionTiming.curve!.y1}, ${node.motionTiming.curve!.x2}, ${node.motionTiming.curve!.y2})'}),
      visibleWhen: ${node.visibleWhen == null ? 'null' : 'const ${_encodeConditionLiteral(node.visibleWhen!)}'},
      interactive: ${node.interactive},
      properties: <String, String>{
$properties      },
    ),
''';
}

String _encodeConditionLiteral(SceneCondition condition) {
  return switch (condition) {
    ScenePredicateCondition(:final predicate) =>
      'ScenePredicateCondition(ScenePredicate.${predicate.name})',
    SceneAll(:final conditions) =>
      'SceneAll(<SceneCondition>[${conditions.map(_encodeConditionLiteral).join(', ')}])',
    SceneAny(:final conditions) =>
      'SceneAny(<SceneCondition>[${conditions.map(_encodeConditionLiteral).join(', ')}])',
    SceneNot(:final condition) =>
      'SceneNot(${_encodeConditionLiteral(condition)})',
  };
}

String _encodeStyle(SceneStyle style) =>
    '''const SceneStyle(
    fill: ${_encodeColorLiteral(style.fill)}, gradientEnd: ${style.gradientEnd == null ? 'null' : _encodeColorLiteral(style.gradientEnd!)},
    gradientAngle: ${style.gradientAngle}, border: ${_encodeColorLiteral(style.border)}, borderWidth: ${style.borderWidth},
    radius: ${style.radius}, shadow: ${_encodeColorLiteral(style.shadow)}, shadowBlur: ${style.shadowBlur}, shadowY: ${style.shadowY},
    backgroundBlur: ${style.backgroundBlur}, textColor: ${style.textColor == null ? 'null' : _encodeColorLiteral(style.textColor!)},
    fontSize: ${style.fontSize}, opacity: ${style.opacity},
  )''';

/// Stable getter name shared by generated scenes and synthesized entrypoints.
String getSceneDocumentVariableName(String id) {
  final parts = id.split(RegExp(r'[^A-Za-z0-9]+'))
    ..removeWhere((part) => part.isEmpty);
  if (parts.isEmpty) {
    return 'generatedSceneDocument';
  }
  final first = parts.first;
  final rest = parts
      .skip(1)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}');
  final name =
      '${first[0].toLowerCase()}${first.substring(1)}${rest.join()}SceneDocument';
  return RegExp(r'^[0-9]').hasMatch(name) ? 'scene$name' : name;
}

/// Encodes a single-quoted Dart literal without interpolation.
String encodeDartString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$escaped'";
}

String _encodeDartNullableString(String? value) {
  return value == null ? 'null' : encodeDartString(value);
}

String _encodeColorLiteral(int value) {
  return '0x${value.toRadixString(16).padLeft(8, '0')}';
}
