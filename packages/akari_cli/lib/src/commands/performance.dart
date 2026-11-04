import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../theme/project.dart';
import '../theme/scene_generation.dart';
import '../execution/model.dart';
import '../execution/paths.dart';
import '../sdk_commands.dart';
import 'plan.dart';

/// Only the transport is shared. Themes own their commands, test journeys,
/// metrics, baselines, and the contents of every reported artifact.
List<String> getThemePerfCommand(ThemePackage theme, String operation) {
  final manifest = loadYaml(
    File('${theme.directory.path}/pubspec.yaml').readAsStringSync(),
  ) as YamlMap;
  final perf = manifest['perf'];
  if (perf == null) {
    throw FormatException('${theme.packageName} does not support $operation.');
  }
  if (perf is! YamlMap || perf['version'] != 1) {
    throw const FormatException('Theme perf configuration requires version 1.');
  }
  final command = perf[operation];
  if (command == null) {
    throw FormatException('${theme.packageName} does not support $operation.');
  }
  if (command is! YamlList ||
      command.isEmpty ||
      command.any((argument) => argument is! String) ||
      (command.first as String).isEmpty) {
    throw FormatException('perf.$operation must be a non-empty command array.');
  }
  return command.cast<String>().toList();
}

/// Validates the result envelope and artifact containment, leaving metric
/// formats and thresholds to the theme. Returned paths are canonical files
/// beneath the output directory, suitable for recording in the run report.
Future<Map<String, String>> getThemePerfArtifacts(File manifest) async {
  final result = jsonDecode(await manifest.readAsString());
  if (result is! Map<String, dynamic> || result['version'] != 1) {
    throw const FormatException('Theme perf result requires version 1.');
  }
  final artifacts = result['artifacts'];
  if (artifacts is! List) {
    throw const FormatException(
      'Theme perf result requires an artifacts array.',
    );
  }
  final outputPath = await manifest.parent.resolveSymbolicLinks();
  final paths = <String, String>{};
  for (final artifact in artifacts) {
    if (artifact is! Map<String, dynamic>) {
      throw const FormatException('Each perf artifact must be an object.');
    }
    final name = artifact['name'];
    final path = artifact['path'];
    if (name is! String || name.isEmpty || paths.containsKey(name)) {
      throw const FormatException(
        'Perf artifact names must be non-empty and unique.',
      );
    }
    if (path is! String || path.isEmpty || File(path).isAbsolute) {
      throw const FormatException(
        'Perf artifact paths must be relative to the output directory.',
      );
    }
    final file = File('$outputPath/$path');
    // Lexical checks alone cannot catch a relative path through a symlink to
    // a file outside the output directory. Resolve before testing containment.
    final resolvedPath = await file.resolveSymbolicLinks();
    if (!resolvedPath.startsWith('$outputPath${Platform.pathSeparator}')) {
      throw FormatException(
        'Perf artifact escapes the output directory: $path',
      );
    }
    paths[name] = resolvedPath;
  }
  return paths;
}

RunPlan createPerformancePlan(
  String operation,
  Directory repoRoot,
  String runDirectory,
  ThemePackage theme,
  List<String> themeArguments,
) {
  final entrypoint = getThemePerfCommand(theme, operation);
  final executable = switch (entrypoint.first) {
    'dart' => getDartCommand(repoRoot),
    'flutter' => getFlutterCommand(repoRoot),
    final executable => [executable],
  };
  final output = '$runDirectory/perf';
  final outputDirectory = Directory(getAbsolutePath(repoRoot, output));
  return RunPlan(
    command: operation == 'verify' ? 'verify-perf' : 'trace-perf',
    themes: [theme],
    artifactPaths: {
      'performance_output': output,
      'performance_result': '$output/result.json',
    },
    getCompletion: (result) => getPerformanceCompletion(
      repoRoot,
      File(getAbsolutePath(repoRoot, '$output/result.json')),
      result,
    ),
    steps: [
      RunStep(
        id: 'theme.pub_get',
        command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
        workingDirectory: theme.directory.path,
      ),
      ...createSceneGenerationSteps(repoRoot, [theme]),
      RunStep(
        id: 'theme.perf.prepare_output',
        command: ['mkdir', '-p', outputDirectory.path],
        action: () => outputDirectory.create(recursive: true),
      ),
      RunStep(
        id: 'theme.perf.$operation',
        command: [...executable, ...entrypoint.skip(1), ...themeArguments],
        workingDirectory: theme.directory.path,
        environment: {
          'AKARI_PERF_OUTPUT_DIR': outputDirectory.path,
          'AKARI_REPO_ROOT': repoRoot.path,
        },
      ),
    ],
  );
}

Future<RunCompletion> getPerformanceCompletion(
  Directory repoRoot,
  File manifest,
  RunResult result,
) async {
  final failureExitCode = result.getFirstFailureExitCode();
  // A failed journey may publish diagnostics; a successful journey must
  // publish a valid manifest before the overall command can pass.
  if (!result.isPassed && !await manifest.exists()) {
    return RunCompletion(failureExitCode: failureExitCode);
  }
  try {
    final artifacts = await getThemePerfArtifacts(manifest);
    return RunCompletion(
      failureExitCode: failureExitCode,
      fields: {
        'theme_artifacts': {
          for (final entry in artifacts.entries)
            entry.key: getRelativePath(repoRoot, entry.value),
        },
      },
    );
  } catch (error) {
    return RunCompletion(error: '$error', failureExitCode: failureExitCode);
  }
}

const collectPerformanceResult = getPerformanceCompletion;
