import 'dart:convert';
import 'dart:io';

import '../execution/model.dart';
import '../execution/paths.dart';
import '../sdk_commands.dart';
import '../theme/build_links.dart';
import '../theme/display_profile.dart';
import '../theme/host.dart';
import '../theme/model.dart';
import '../theme/project.dart';
import '../theme/scene_generation.dart';
import 'plan.dart';

RunPlan createBuildPlan(
  Directory repoRoot,
  ThemePackage theme, {
  required BuildMode mode,
  String platform = 'linux',
  int? jobs,
}) {
  final host = getThemeHostDirectory(theme, ThemeHostKind.greeter);
  return RunPlan(
    command: 'build',
    themes: [theme],
    artifactPaths: {
      'backend_executable': getBackendExecutablePath(BackendMode.real, mode),
      'host_project': host,
      'build_directory': '$host/build/$platform',
      if (platform == 'linux') ...{
        'executable': getLinuxExecutablePath(host, mode),
        ...getBuildLinkPaths(theme),
      },
    },
    steps: [
      _createBackendBuildStep(BackendMode.real, mode, jobs),
      ..._createHostPreparationSteps(
        repoRoot,
        theme,
        ThemeHostKind.greeter,
        host,
      ),
      RunStep(
        id: 'flutter.build_$platform',
        command: [
          ...getFlutterCommand(repoRoot),
          'build',
          platform,
          '--${mode.name}',
          '--no-pub',
          '--dart-define=AKARI_BACKEND=real',
        ],
        workingDirectory: host,
        environment: {if (jobs != null) 'AKARI_BUILD_JOBS': '$jobs'},
      ),
      if (platform == 'linux')
        RunStep(
          id: 'build.links',
          command: [
            ...getDartCommand(repoRoot),
            'tool/build_links.dart',
            repoRoot.path,
            theme.directory.path,
            mode.name,
          ],
          dependencies: const ['backend.build', 'flutter.build_linux'],
          action: () => updateBuildLinks(repoRoot, theme, mode),
        ),
    ],
  );
}

RunPlan createThemeRunPlan(
  Directory repoRoot,
  ThemePackage theme,
  String runDirectory, {
  required ThemeRunTarget target,
  required BuildMode mode,
  required BackendMode backend,
  int? jobs,
  Map<String, Object?>? displayProfile,
  SwayBackend swayBackend = SwayBackend.wayland,
}) {
  final kind = target.hostKind;
  final host = getThemeHostDirectory(theme, kind);
  final hasBackend = kind == ThemeHostKind.greeter;
  final sway = target == ThemeRunTarget.sway;
  final displayReport = '$runDirectory/sway/display-report.json';
  return RunPlan(
    command: target.commandName,
    themes: [theme],
    displayProfile: displayProfile,
    collectResult: sway
        ? (result) => collectDisplayResult(
            File(getAbsolutePath(repoRoot, displayReport)),
            result,
          )
        : null,
    artifactPaths: {
      if (hasBackend)
        'backend_executable': getBackendExecutablePath(backend, mode),
      'host_project': host,
      'build_directory': '$host/build/linux',
      'executable': getLinuxExecutablePath(host, mode),
      if (sway) ...{
        'display_report': displayReport,
        'display_snapshot': '$runDirectory/sway/outputs.json',
        'screenshots': '$runDirectory/sway/screenshots',
        'sway_log': '$runDirectory/sway/sway.log',
        'flutter_log': '$runDirectory/sway/flutter.log',
      },
    },
    steps: [
      if (hasBackend) _createBackendBuildStep(backend, mode, jobs),
      ..._createHostPreparationSteps(repoRoot, theme, kind, host),
      RunStep(
        id: 'theme.${target.stepName}',
        command: [
          if (sway) ...[
            'python3',
            getJoinedPath(repoRoot.path, 'scripts/sway-session.py'),
            '--log-dir',
            getAbsolutePath(repoRoot, '$runDirectory/sway'),
            '--backend',
            swayBackend.name,
            '--',
          ],
          if (hasBackend) ...[
            'bash',
            getJoinedPath(repoRoot.path, 'scripts/debug-dbus.sh'),
          ],
          ...getDartCommand(repoRoot),
          getJoinedPath(repoRoot.path, 'tool/theme_session.dart'),
          theme.directory.path,
          getAbsolutePath(repoRoot, host),
          mode.name,
          kind.backendDefine,
        ],
        workingDirectory: host,
        dependencies: [if (hasBackend) 'backend.build', 'theme.host.pub_get'],
        interactive: true,
        environment: {
          'AKARI_DISPLAY_MODE': kind == ThemeHostKind.studio
              ? 'single'
              : 'mirror',
          'AKARI_WINDOW_MODE':
              Platform.environment['AKARI_WINDOW_MODE'] ??
              (hasBackend ? 'fullscreen' : 'windowed'),
          if (jobs != null) 'AKARI_BUILD_JOBS': '$jobs',
          if (sway) 'AKARI_DISPLAY_PROFILE_JSON': jsonEncode(displayProfile!),
          if (hasBackend) ...{
            'AKARI_BACKEND_MODE': backend.name,
            'AKARI_BACKEND_BIN': getAbsolutePath(
              repoRoot,
              getBackendExecutablePath(backend, mode),
            ),
            'AKARI_LOG_DIR': getAbsolutePath(repoRoot, '$runDirectory/dbus'),
          },
        },
      ),
    ],
  );
}

RunStep _createBackendBuildStep(
  BackendMode backend,
  BuildMode mode,
  int? jobs,
) => RunStep(
  id: 'backend.build',
  command: [
    'cargo',
    'build',
    '--locked',
    '--target-dir',
    getBackendTargetDirectory(backend),
    if (mode != BuildMode.debug) '--release',
    if (backend == BackendMode.mock) ...['--features', 'mock'],
    if (jobs != null) ...['--jobs', '$jobs'],
  ],
  workingDirectory: 'backend',
  dependencies: const [],
);

List<RunStep> _createHostPreparationSteps(
  Directory repoRoot,
  ThemePackage theme,
  ThemeHostKind kind,
  String host,
) => [
  RunStep(
    id: 'theme.pub_get',
    command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
    workingDirectory: theme.directory.path,
    dependencies: const [],
  ),
  ...createSceneGenerationSteps(repoRoot, [theme]),
  RunStep(
    id: 'theme.host.generate',
    command: [
      ...getDartCommand(repoRoot),
      'tool/theme_host.dart',
      theme.directory.path,
      getAbsolutePath(repoRoot, host),
      if (kind == ThemeHostKind.studio)
        '--studio'
      else if (kind == ThemeHostKind.preview)
        '--preview',
    ],
    action: () => createThemeHost(
      repoRoot: repoRoot,
      theme: theme,
      output: Directory(getAbsolutePath(repoRoot, host)),
      kind: kind,
    ),
  ),
  RunStep(
    id: 'theme.host.pub_get',
    command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
    workingDirectory: host,
  ),
];
