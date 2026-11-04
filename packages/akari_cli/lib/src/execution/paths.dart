import 'dart:io';

String getAbsolutePath(Directory repoRoot, String path) {
  return File(path).isAbsolute ? path : getJoinedPath(repoRoot.path, path);
}

String getRelativePath(Directory repoRoot, String path) {
  final absolutePath = File(path).absolute.path;
  final rootPath = repoRoot.absolute.path;
  if (absolutePath == rootPath) {
    return '.';
  }
  if (absolutePath.startsWith('$rootPath${Platform.pathSeparator}')) {
    return absolutePath.substring(rootPath.length + 1);
  }
  return absolutePath;
}

String getJoinedPath(String base, String relative) {
  return '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
}

Directory findUserHomeDirectory({
  String requiredMessage = 'HOME is required.',
}) {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw FormatException(requiredMessage);
  }
  return Directory(home);
}

/// Source entrypoints locate their checkout by ancestry; compiled executables
/// can use the invocation directory or an explicit AKARI_REPO_ROOT.
Directory findRepositoryRoot() {
  final configured = Platform.environment['AKARI_REPO_ROOT'];
  final starts = configured == null
      ? [File.fromUri(Platform.script).parent.absolute, Directory.current]
      : [Directory(configured).absolute];
  for (var directory in starts) {
    while (true) {
      if (File(getJoinedPath(directory.path, 'crates/Cargo.toml'))
              .existsSync() &&
          File(getJoinedPath(directory.path, 'packages/akari_cli/pubspec.yaml'))
              .existsSync()) {
        return directory;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
  }
  throw StateError(
    'Could not locate the Akari repository root. Set AKARI_REPO_ROOT.',
  );
}
