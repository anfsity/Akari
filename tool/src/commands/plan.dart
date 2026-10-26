import '../execution/model.dart';
import '../theme/project.dart';

/// One authoritative description feeds dry-run, locking, execution and reports.
/// Result collection stays within the run's report and lock lifetime, allowing
/// performance and display workflows to enforce their own success contracts.
class RunPlan {
  const RunPlan({
    required this.command,
    required this.steps,
    this.artifactPaths = const {},
    this.themes = const [],
    Future<RunCompletion> Function(RunResult)? getCompletion,
    Future<RunCompletion> Function(RunResult)? collectResult,
    this.displayProfile,
  }) : getCompletion = getCompletion ?? collectResult;

  final String command;
  final List<RunStep> steps;
  final Map<String, String> artifactPaths;
  final List<ThemePackage> themes;
  final Future<RunCompletion> Function(RunResult)? getCompletion;
  Future<RunCompletion> Function(RunResult)? get collectResult => getCompletion;
  final Map<String, Object?>? displayProfile;
}
