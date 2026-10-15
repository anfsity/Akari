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
        'splash_executable': getSplashExecutablePath(mode),
        ...getBuildLinkPaths(theme),
      },
    },
    steps: [
      _createBackendBuildStep(BackendMode.real, mode, jobs),
      if (platform == 'linux') _createSplashBuildStep(mode, jobs),
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
          dependencies: const [
            'backend.build',
            'splash.build',
            'flutter.build_linux',
          ],
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
  String? splashDuration,
}) {
  final kind = target.hostKind;
  final themes = kind == ThemeHostKind.studio
      ? findStudioThemePackages(repoRoot, theme)
      : [theme];
  final host = getThemeHostDirectory(theme, kind);
  final hasBackend = kind == ThemeHostKind.greeter;
  final sway = target == ThemeRunTarget.sway;
  final preview = target == ThemeRunTarget.preview;
  final splash = Platform.environment['AKARI_SPLASH_BIN'];
  final displayReport = '$runDirectory/sway/display-report.json';
  return RunPlan(
    command: target.commandName,
    themes: themes,
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
      if (preview) 'splash_executable': splash ?? getSplashExecutablePath(mode),
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
      ..._createHostPreparationSteps(
        repoRoot,
        theme,
        kind,
        host,
        themes: themes,
      ),
      if (preview) ...[
        if (splash == null) _createSplashBuildStep(mode, jobs),
        RunStep(
          id: 'theme.preview.build',
          command: [
            ...getFlutterCommand(repoRoot),
            'build',
            'linux',
            '--${mode.name}',
            '--no-pub',
            '--dart-define=AKARI_BACKEND=demo',
          ],
          workingDirectory: host,
          dependencies: const ['theme.host.pub_get'],
          environment: {if (jobs != null) 'AKARI_BUILD_JOBS': '$jobs'},
        ),
      ],
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
        dependencies: [
          if (hasBackend) 'backend.build',
          if (preview) ...[
            if (splash == null) 'splash.build',
            'theme.preview.build',
          ] else
            'theme.host.pub_get',
        ],
        interactive: true,
        environment: {
          if (kind == ThemeHostKind.studio)
            'AKARI_THEME_DIRECTORIES_JSON': jsonEncode(
              themes.map((project) => project.directory.path).toList(),
            ),
          'AKARI_DISPLAY_MODE': kind == ThemeHostKind.studio
              ? 'single'
              : 'mirror',
          'AKARI_WINDOW_MODE':
              Platform.environment['AKARI_WINDOW_MODE'] ??
              (hasBackend ? 'fullscreen' : 'windowed'),
          if (jobs != null) 'AKARI_BUILD_JOBS': '$jobs',
          if (preview) ...{
            'AKARI_SPLASH_BIN':
                splash ??
                getAbsolutePath(repoRoot, getSplashExecutablePath(mode)),
            'AKARI_PREVIEW_APPLICATION': getAbsolutePath(
              repoRoot,
              getLinuxExecutablePath(host, mode),
            ),
            'AKARI_SPLASH_DURATION': ?splashDuration,
          },
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

RunStep _createSplashBuildStep(BuildMode mode, int? jobs) => RunStep(
  id: 'splash.build',
  command: [
    'cargo',
    'build',
    '--locked',
    '--target-dir',
    '../build/tool/splash',
    if (mode != BuildMode.debug) '--release',
    if (jobs != null) ...['--jobs', '$jobs'],
  ],
  workingDirectory: 'splash',
  dependencies: const [],
);

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
  String host, {
  List<ThemePackage>? themes,
}) {
  final projects = themes ?? [theme];
  return [
    for (final project in projects)
      RunStep(
        id: project.packageName == theme.packageName
            ? 'theme.pub_get'
            : '${project.packageName}.pub_get',
        command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
        workingDirectory: project.directory.path,
        dependencies: const [],
      ),
    ...createSceneGenerationSteps(repoRoot, projects),
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
        studioThemes: projects,
      ),
    ),
    RunStep(
      id: 'theme.host.pub_get',
      command: [...getFlutterCommand(repoRoot), 'pub', 'get'],
      workingDirectory: host,
    ),
  ];
}
