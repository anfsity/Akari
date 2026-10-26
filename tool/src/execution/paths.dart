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

