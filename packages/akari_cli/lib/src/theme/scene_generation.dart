import 'dart:io';

import '../execution/model.dart';
import '../sdk_commands.dart';
import 'project.dart';

List<RunStep> createSceneGenerationSteps(
  Directory repoRoot,
  List<ThemePackage> themes, {
  List<String> Function(ThemePackage)? dependenciesFor,
}) {
  return [
    for (final theme in themes)
      RunStep(
        id: 'scenes.generate_${theme.packageName}',
        command: [...getDartCommand(repoRoot), 'run', 'build_runner', 'build'],
        workingDirectory: theme.directory.path,
        dependencies: dependenciesFor?.call(theme) ?? const [],
      ),
  ];
}
