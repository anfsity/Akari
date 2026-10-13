import 'package:build/build.dart';

import 'scene_codegen.dart';

export 'scene_codegen.dart';

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
