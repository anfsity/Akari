import 'package:build/build.dart';
import 'package:scene_schema/scene_schema.dart';

Builder sceneBuilder(BuilderOptions options) => SceneBuilder();

/// Converts authoring JSON to typed Dart during the theme build. Validation is
/// delegated to scene_schema so generated scenes and editor tooling agree on
/// the accepted document contract.
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
  final document = decodeSceneDocument(input);
  // A getter creates a fresh document after hot reload. A cached top-level
  // final would keep the old scene even after regenerated code is loaded.
  return '''// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated from ${document.id}.scene.json.
import 'package:scene/scene.dart';

SceneDocument get ${_getVariableName(document.id)} => SceneDocument(
  id: ${_encodeDartString(document.id)},
  version: ${document.version},
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
  ),
  nodes: <SceneNode>[
${document.nodes.map(_encodeNode).join()}  ],
);

''';
}

String _encodeNode(SceneNode node) {
  final properties = [
    for (final entry in node.properties.entries)
      '        ${_encodeDartString(entry.key)}: ${_encodeDartString(entry.value)},\n',
  ].join();
  return '''    SceneNode(
      id: ${_encodeDartString(node.id)},
      componentId: ${_encodeDartString(node.componentId)},
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
      visibleWhen: ${node.visibleWhen == null ? 'null' : 'const ${_encodeConditionLiteral(node.visibleWhen!)}'},
      interactive: ${node.interactive},
      properties: <String, String>{
${properties}      },
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

String _getVariableName(String id) {
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

String _encodeDartString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$escaped'";
}

String _encodeDartNullableString(String? value) {
  return value == null ? 'null' : _encodeDartString(value);
}

String _encodeColorLiteral(int value) {
  return '0x${value.toRadixString(16).padLeft(8, '0')}';
}
