import 'dart:io';

/// Walks up from the working directory to the repository root.
///
/// The editor runs from inside its package, so the root is located by a theme
/// package rather than a fixed relative path.
Directory? repoRoot() {
  var directory = Directory.current;
  for (var depth = 0; depth < 8; depth++) {
    final marker = File(
      '${directory.path}/packages/mozais_theme_default/pubspec.yaml',
    );
    if (marker.existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }
  return null;
}

/// The bundled default scene inside its theme package.
String? defaultScenePath() {
  final root = repoRoot();
  if (root == null) {
    return null;
  }
  final candidate = File(
    '${root.path}/packages/mozais_theme_default/lib/default.scene.json',
  );
  return candidate.existsSync() ? candidate.path : null;
}

/// Resolves a document asset path against the repository root.
File? repoAssetFile(String asset) {
  final root = repoRoot();
  if (root == null) {
    return null;
  }
  return File('${root.path}/$asset');
}

/// The repository directory that document `assets/...` paths live in.
Directory? repoAssetsDirectory() {
  final root = repoRoot();
  return root == null ? null : Directory('${root.path}/assets');
}

/// The scene to open at startup.
///
/// A configured path is used only while it exists; otherwise the bundled
/// default is used, so a stale setting after a move cannot break startup.
String resolveStartupScenePath(String configured) {
  if (configured.isNotEmpty && File(configured).existsSync()) {
    return configured;
  }
  return defaultScenePath() ?? '';
}
