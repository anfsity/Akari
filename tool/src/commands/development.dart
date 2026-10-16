import 'dart:io';

import '../cli/arguments.dart';
import '../cli/definition.dart';
import '../execution/model.dart';
import '../execution/paths.dart';
import '../execution/report.dart';
import '../execution/runner.dart';
import '../theme/display_profile.dart';
import '../theme/project.dart';
import '../theme/scene_generation.dart';
import 'performance.dart';
import 'plan.dart';
import 'theme.dart';
import 'verification.dart';

Future<int> runDevelopmentCommand(
  DevCommandOptions options,
  Directory repoRoot,
) async {
  final command = options.command;
  final themes = command == DevelopmentCommand.splash
      ? <ThemePackage>[]
      : options.themePath != null || command.isThemeSelectionRequired
      ? [
          getThemePackage(
            Directory(options.themePath ?? '${repoRoot.path}/themes/default'),
          ),
        ]
      : findThemePackages(repoRoot);
  final display = command == DevelopmentCommand.sway
      ? await resolveDisplayProfile(
          repoRoot,
          profile: options.displayProfile,
          dryRun: options.dryRun,
          resolution: options.resolution,
          scale: options.scale,
        )
      : null;
  final runDirectory = await _createRunDirectory(
    repoRoot,
    reserve: !options.dryRun,
  );
  final plan = switch (command) {
    DevelopmentCommand.splash => createSplashRunPlan(
      repoRoot,
      mode: options.buildMode,
      jobs: options.jobs,
      light: options.splashLight,
    ),
    DevelopmentCommand.build => createBuildPlan(
      repoRoot,
      themes.single,
      mode: options.buildMode,
      platform: options.buildTarget,
      jobs: options.jobs,
    ),
    DevelopmentCommand.run ||
    DevelopmentCommand.sway ||
    DevelopmentCommand.studio => createThemeRunPlan(
      repoRoot,
      themes.single,
      runDirectory,
      target: command.runTarget!,
      mode: options.buildMode,
      backend: options.backendMode,
      jobs: options.jobs,
      displayProfile: display,
      swayBackend: options.swayBackend,
    ),
    DevelopmentCommand.preview => createPreviewPlan(
      repoRoot,
      themes.single,
      runDirectory,
      jobs: options.jobs,
      scenario: options.previewScenario,
    ),
    DevelopmentCommand.verify => createVerificationPlan(
      repoRoot,
      runDirectory,
      themes,
      selectedThemeOnly: options.themePath != null,
    ),
    DevelopmentCommand.verifyPerf ||
    DevelopmentCommand.tracePerf => await preparePerformanceRun(
      command == DevelopmentCommand.verifyPerf ? 'verify' : 'trace',
      repoRoot,
      runDirectory,
      themes.single,
      options.themeArguments,
      dryRun: options.dryRun,
    ),
    DevelopmentCommand.generateScenes => RunPlan(
      command: 'generate-scenes',
      themes: themes,
      steps: createSceneGenerationSteps(repoRoot, themes),
    ),
  };
  return runPlan(
    plan,
    repoRoot: repoRoot,
    runDirectory: runDirectory,
    format: options.format,
    reportPath: options.reportPath,
    dryRun: options.dryRun,
  );
}

Future<int> runPlan(
  RunPlan plan, {
  required Directory repoRoot,
  required String runDirectory,
  required RunOutputFormat format,
  String? reportPath,
  bool dryRun = false,
}) async {
  final report = RunReport(
    command: plan.command,
    steps: plan.steps,
    artifactPaths: plan.artifactPaths,
    repoRoot: repoRoot,
    runDirectory: runDirectory,
    format: format,
    reportPath: reportPath,
    displayProfile: plan.displayProfile,
  );
  if (dryRun) {
    report.writePlan();
    return 0;
  }
  final locks = <RandomAccessFile>[];
  try {
    // Generated sources belong to the theme. Hold its lock through result
    // collection and live sessions, not merely through the initial build.
    for (final theme in plan.themes) {
      final file = File(
        '${repoRoot.path}/build/tool/locks/${getThemeCacheKey(theme)}/theme.lock',
      );
      await file.parent.create(recursive: true);
      final lock = await file.open(mode: FileMode.append);
      locks.add(lock);
      await lock.lock(FileLock.blockingExclusive);
    }
    await report.start();
    try {
      final result = await runSteps(plan.steps, report);
      final completion =
          await plan.collectResult?.call(result) ?? const RunCompletion();
      return await report.finish(result, completion);
    } finally {
      await report.close();
    }
  } finally {
    for (final lock in locks.reversed) {
      await lock.close();
    }
  }
}

Future<String> _createRunDirectory(
  Directory repoRoot, {
  required bool reserve,
}) async {
  final parentPath = getJoinedPath(repoRoot.path, 'build/tool/runs');
  if (reserve) {
    await Directory(parentPath).create(recursive: true);
  }

  final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  var collision = 0;
  while (true) {
    final runId = collision == 0
        ? '$timestamp-$pid'
        : '$timestamp-$pid-$collision';
    final runDirectory = 'build/tool/runs/$runId';
    final directory = Directory(getJoinedPath(repoRoot.path, runDirectory));
    if (directory.existsSync()) {
      collision++;
      continue;
    }
    if (!reserve) {
      return runDirectory;
    }

    try {
      await directory.create();
      return runDirectory;
    } on FileSystemException {
      if (!directory.existsSync()) {
        rethrow;
      }
      collision++;
    }
  }
}
