import 'dart:io';

// Session startup needs only SDK resolution; keep it independent of command
// planning, YAML manifests, and reporting to avoid loading those libraries again.
List<String> getFlutterCommand(Directory repoRoot) {
  final customFlutter = Platform.environment['MOZAIS_FLUTTER_BIN'];
  if (customFlutter != null && customFlutter.isNotEmpty) {
    return [_resolveSdkBinary(customFlutter, repoRoot)];
  }
  final localFlutter = File(
    _join(repoRoot.path, '.fvm/flutter_sdk/bin/flutter'),
  );
  return localFlutter.existsSync() ? [localFlutter.path] : ['fvm', 'flutter'];
}

List<String> getDartCommand(Directory repoRoot) {
  final customDart = Platform.environment['MOZAIS_DART_BIN'];
  if (customDart != null && customDart.isNotEmpty) {
    return [_resolveSdkBinary(customDart, repoRoot)];
  }
  final customFlutter = Platform.environment['MOZAIS_FLUTTER_BIN'];
  if (customFlutter != null && customFlutter.isNotEmpty) {
    final flutterPath = _resolveSdkBinary(customFlutter, repoRoot);
    return [_join(File(flutterPath).parent.path, 'dart')];
  }
  final localDart = File(_join(repoRoot.path, '.fvm/flutter_sdk/bin/dart'));
  return localDart.existsSync() ? [localDart.path] : ['fvm', 'dart'];
}

String _resolveSdkBinary(String binary, Directory repoRoot) {
  final file = File(binary);
  return file.isAbsolute ? binary : _join(repoRoot.path, binary);
}

String _join(String base, String relative) {
  return '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
}
