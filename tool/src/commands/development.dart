import 'dart:convert';
import 'dart:io';

import '../execution/model.dart';
import '../execution/paths.dart';
import '../execution/report.dart';
import '../execution/runner.dart';
import '../theme_perf.dart';

Future<int> runDevCommand({
  required String command,
  required RunOutputFormat format,
  required String? reportPath,
  required Directory repoRoot,
  required String runDirectory,
  required List<RunStep> steps,
  required Map<String, String> artifactPaths,
  Map<String, Object?>? displayProfile,
}) async {
  final performanceOutput = artifactPaths['performance_output'];
  if (performanceOutput != null) {
    await Directory(getAbsolutePath(repoRoot, performanceOutput))
        .create(recursive: true);
  }
  final report = RunReport(
    command: command,
    format: format,
    reportPath: reportPath,
    repoRoot: repoRoot,
    runDirectory: runDirectory,
    steps: steps,
    artifactPaths: artifactPaths,
    displayProfile: displayProfile,
  );
  await report.start();
  try {
    final result = await runSteps(steps, report);
    Map<String, String>? themeArtifacts;
    String? reportError;
    final performanceResultPath = artifactPaths['performance_result'];
    if (performanceResultPath != null) {
      final manifest = File(getAbsolutePath(repoRoot, performanceResultPath));
      final commandPassed = result.isPassed;
      // A failed theme may still publish diagnostic artifacts. A successful
      // theme must supply a valid manifest before the run can be reported passed.
      if (commandPassed || await manifest.exists()) {
        try {
          themeArtifacts = {
            for (final entry in (await getThemePerfArtifacts(manifest)).entries)
              entry.key: getRelativePath(repoRoot, entry.value),
          };
        } catch (error) {
          reportError = '$error';
        }
      }
    }
    Map<String, Object?>? displayReport = displayProfile;
    final displayReportPath = artifactPaths['display_report'];
    if (displayReportPath != null) {
      final file = File(getAbsolutePath(repoRoot, displayReportPath));
      if (await file.exists()) {
        try {
          displayReport = (jsonDecode(await file.readAsString()) as Map)
              .cast<String, Object?>();
          if (displayReport['matched'] != true) {
            reportError =
                '${displayReport['error'] ?? 'Sway outputs did not match the requested profile.'}';
          }
        } catch (error) {
          reportError = 'Could not read Sway display report: $error';
        }
      } else if (result.isPassed) {
        reportError = 'Sway session did not publish its display report.';
      }
    }
    return await report.finish(
      result,
      RunCompletion(
        fields: {'display': ?displayReport, 'theme_artifacts': ?themeArtifacts},
        error: reportError,
        failureExitCode: performanceResultPath == null
            ? 1
            : result.getFirstFailureExitCode(),
      ),
    );
  } finally {
    await report.close();
  }
}
