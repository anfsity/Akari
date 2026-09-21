import 'dart:io';

/// Walks up from the working directory to the repository root.
///
/// The editor runs from inside its package, so the root is located by the
/// `mozais_greeter_ui` package rather than a fixed relative path.
Directory? repoRoot() {
  var directory = Directory.current;
  for (var depth = 0; depth < 8; depth++) {
    final marker = File(
      '${directory.path}/packages/mozais_greeter_ui/pubspec.yaml',
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

/// The bundled default scene inside the UI package.
String? defaultScenePath() {
  final root = repoRoot();
  if (root == null) {
    return null;
  }
  final candidate = File(
    '${root.path}/packages/mozais_greeter_ui/lib/themes/default/default.scene.json',
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
