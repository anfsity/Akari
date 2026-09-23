import 'package:build/build.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

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
  return _generate(decodeSceneDocument(input));
}

String _generate(SceneDocument document) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// Generated from ${document.id}.scene.json.')
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
    ..writeln('    referenceWidth: ${document.canvas.referenceWidth},')
    ..writeln('    referenceHeight: ${document.canvas.referenceHeight},')
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
      ..writeln(
        '      visibleWhen: ${node.visibleWhen == null ? 'null' : 'const ${_conditionLiteral(node.visibleWhen!)}'},',
      )
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

String _conditionLiteral(SceneCondition condition) {
  return switch (condition) {
    ScenePredicateCondition(:final predicate) =>
      'ScenePredicateCondition(ScenePredicate.${predicate.name})',
    SceneAll(:final conditions) =>
      'SceneAll(<SceneCondition>[${conditions.map(_conditionLiteral).join(', ')}])',
    SceneAny(:final conditions) =>
      'SceneAny(<SceneCondition>[${conditions.map(_conditionLiteral).join(', ')}])',
    SceneNot(:final condition) => 'SceneNot(${_conditionLiteral(condition)})',
  };
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

String _colorLiteral(int value) {
  return '0x${value.toRadixString(16).padLeft(8, '0')}';
}
