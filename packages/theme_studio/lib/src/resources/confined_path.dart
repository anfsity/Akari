import 'dart:io';

/// Returns [path] without a redundant trailing separator (preserving root `/`).
String trimTrailingSeparator(String path) {
  return path.length > 1 && path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
}

/// Returns whether [candidatePath] equals [rootPath] or lies strictly beneath it.
bool isCanonicalPathWithin(String rootPath, String candidatePath) {
  if (candidatePath == rootPath) return true;
  final prefix = rootPath.endsWith(Platform.pathSeparator)
      ? rootPath
      : '$rootPath${Platform.pathSeparator}';
  return candidatePath.startsWith(prefix);
}

/// Validates a slash-separated relative asset/include path without traversal or
/// separator tricks, returning its individual path segments when safe.
List<String>? parseSafeRelativeSegments(String relative) {
  if (relative.isEmpty ||
      relative.contains('\\') ||
      relative.contains('\u0000')) {
    return null;
  }
  final segments = relative.split('/');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    return null;
  }
  return segments;
}

/// Resolves [relative] beneath [root], rejecting lexical traversal, escaping
/// symlinks, and dangling symlinks along existing path prefixes.
File? findConfinedFile(Directory root, String relative) {
  final segments = parseSafeRelativeSegments(relative);
  if (segments == null || !root.existsSync()) return null;
  final rootPath = root.resolveSymbolicLinksSync();
  final displayRoot = trimTrailingSeparator(root.path);
  final displayPrefix = displayRoot == Platform.pathSeparator
      ? Platform.pathSeparator
      : '$displayRoot/';
  var current = rootPath;
  for (final segment in segments) {
    current = '$current${Platform.pathSeparator}$segment';
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return File('$displayPrefix${segments.join('/')}');
    }
    try {
      final resolved = type == FileSystemEntityType.directory
          ? Directory(current).resolveSymbolicLinksSync()
          : File(current).resolveSymbolicLinksSync();
      if (!isCanonicalPathWithin(rootPath, resolved)) return null;
      current = resolved;
    } on FileSystemException {
      return null;
    }
  }
  return File('$displayPrefix${segments.join('/')}');
}

/// Writes [contents] to [target] via a sibling temporary directory rename so
/// failed writes never leave a partially written target file.
void writeFileAtomically(
  File target,
  String contents, {
  String tempPrefix = '.akari-studio-',
  String tempName = 'file',
}) {
  target.parent.createSync(recursive: true);
  final temporaryDirectory = target.parent.createTempSync(tempPrefix);
  try {
    final temporary = File('${temporaryDirectory.path}/$tempName');
    temporary.writeAsStringSync(contents, flush: true);
    temporary.renameSync(target.path);
  } finally {
    temporaryDirectory.deleteSync(recursive: true);
  }
}
