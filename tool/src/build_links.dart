import 'dart:io';

import 'theme_project.dart';

Map<String, String> getBuildLinkPaths(ThemePackage theme) => {
  'bundle_link': 'build/out/${theme.packageName.substring('theme_'.length)}',
  'backend_link': 'build/out/backend',
};

Future<void> updateBuildLinks(
  Directory repoRoot,
  ThemePackage theme,
  String buildMode,
) async {
  final host = getThemeHostDirectory(theme, preview: false);
  final frontend = getLinuxExecutablePath(host, buildMode);
  final backend =
      'backend/target/mozais-real/${buildMode == 'debug' ? 'debug' : 'release'}/backend';
  final targets = {
    'bundle_link': File(frontend).parent.path,
    'backend_link': backend,
  };
  final paths = getBuildLinkPaths(theme);
  if (paths['bundle_link'] == paths['backend_link']) {
    throw const FormatException(
      'Theme name backend conflicts with the backend link.',
    );
  }
  final output = Directory('${repoRoot.path}/build/out');
  await output.create(recursive: true);
  final lock = await File('${output.path}/.links.lock')
      .open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.blockingExclusive);
    for (final entry in paths.entries) {
      final linkPath = '${repoRoot.path}/${entry.value}';
      final type = await FileSystemEntity.type(linkPath, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.link) {
        throw FileSystemException('Build output path is not a link', linkPath);
      }
      if (entry.key == 'bundle_link' && type == FileSystemEntityType.link) {
        final target = Uri.directory(output.path)
            .resolve(await Link(linkPath).target())
            .normalizePath()
            .toFilePath();
        if (!target.startsWith('${repoRoot.path}/$host/build/')) {
          throw FileSystemException(
            'Build output belongs to a different theme project',
            linkPath,
          );
        }
      }
    }
    for (final executable in [frontend, backend]) {
      if (!await File('${repoRoot.path}/$executable').exists()) {
        throw FileSystemException('Build artifact is missing', executable);
      }
    }
    // Rename each relative symlink in place so readers never observe a gap.
    // These are cache links; subsequent builds can modify their targets.
    for (final entry in paths.entries) {
      final link = Link('${output.path}/.link-$pid');
      try {
        await link.create('../../${targets[entry.key]}');
        await link.rename('${repoRoot.path}/${entry.value}');
      } finally {
        if (await link.exists()) await link.delete();
      }
    }
  } finally {
    await lock.close();
  }
}
