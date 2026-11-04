import 'dart:convert';
import 'dart:io';

import '../execution/model.dart';
import '../execution/paths.dart';

Future<Map<String, Object?>> resolveDisplayProfile(
  Directory repoRoot, {
  required String profile,
  required bool dryRun,
  String? resolution,
  String? scale,
}) async {
  final stateHome = Platform.environment['XDG_STATE_HOME'];
  final String state;
  if (stateHome != null && stateHome.isNotEmpty) {
    state = stateHome;
  } else {
    final home = findUserHomeDirectory(
      requiredMessage: 'HOME or XDG_STATE_HOME is required.',
    ).path;
    state = '$home/.local/state';
  }
  final result = await Process.run('python3', [
    getJoinedPath(repoRoot.path, 'scripts/greetd-test/display_profile.py'),
    '--reference',
    getJoinedPath(repoRoot.path, 'config/sway/reference.json'),
    '--state',
    '$state/akari/display-profiles',
    '--display-profile',
    profile,
    if (resolution != null) ...['--resolution', resolution],
    if (scale != null) ...['--scale', scale],
    if (dryRun) '--dry-run',
  ]);
  if ((result.stderr as String).isNotEmpty) stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw DisplayProfileFailure(result.exitCode);
  }
  return (jsonDecode(result.stdout as String) as Map).cast<String, Object?>();
}

class DisplayProfileFailure implements Exception {
  const DisplayProfileFailure(this.exitCode);
  final int exitCode;
}

Future<RunCompletion> getDisplayCompletion(File file, RunResult result) async {
  if (!await file.exists()) {
    return RunCompletion(
      error: result.isPassed
          ? 'Sway session did not publish its display report.'
          : null,
    );
  }
  try {
    final display = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    return RunCompletion(
      fields: {'display': display},
      error: display['matched'] == true
          ? null
          : '${display['error'] ?? 'Sway outputs did not match the requested profile.'}',
    );
  } catch (error) {
    return RunCompletion(error: 'Could not read Sway display report: $error');
  }
}

const collectDisplayResult = getDisplayCompletion;
