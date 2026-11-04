import 'dart:io';

enum ScriptKind { tool, internal, library }

/// Calling conditions belong to the script contract, not its file extension.
/// Keep every repository script classified, including non-executable libraries.
class ScriptDefinition {
  const ScriptDefinition(this.path, this.kind, this.description);

  final String path;
  final ScriptKind kind;
  final String description;

  String get interpreter => path.endsWith('.py') ? 'python3' : 'bash';
}

const repositoryScripts = [
  ScriptDefinition(
    'bootstrap-toolchain.sh',
    ScriptKind.tool,
    'Install the configured Flutter SDK and fetch dependencies.',
  ),
  ScriptDefinition(
    'check-toolchain.sh',
    ScriptKind.tool,
    'Check native tools and SDK dependencies.',
  ),
  ScriptDefinition(
    'build-api-docs.sh',
    ScriptKind.tool,
    'Build Dart API documentation.',
  ),
  ScriptDefinition(
    'verify-docs.py',
    ScriptKind.tool,
    'Check a built documentation site; requires the site directory.',
  ),
  ScriptDefinition(
    'run-backend.sh',
    ScriptKind.tool,
    'Build and run the backend; requires a session D-Bus.',
  ),
  ScriptDefinition(
    'debug-dbus.sh',
    ScriptKind.tool,
    'Run a command with a backend on a private D-Bus.',
  ),
  ScriptDefinition(
    'sway-session.py',
    ScriptKind.tool,
    'Run a command in isolated Sway; requires --log-dir.',
  ),
  ScriptDefinition(
    'lib.sh',
    ScriptKind.library,
    'Shared Bash functions; source from another script.',
  ),
  ScriptDefinition(
    'splash.sh',
    ScriptKind.internal,
    'VT splash then command; requires AKARI_SPLASH_BIN, AKARI_LOG_DIR and a real VT.',
  ),
  ScriptDefinition(
    'login/manage.py',
    ScriptKind.tool,
    'Manage installed login resources; mutations require root.',
  ),
  ScriptDefinition(
    'login/launch.sh',
    ScriptKind.internal,
    'Installed greetd entrypoint; requires the deployed release layout and greeter account.',
  ),
  ScriptDefinition(
    'login/run-greeter.sh',
    ScriptKind.internal,
    'Sway child; requires the installed AKARI_RELEASE, AKARI_APP, AKARI_LOG_DIR, AKARI_SPLASH_BIN and private bus.',
  ),
  ScriptDefinition(
    'greetd-test/install.sh',
    ScriptKind.tool,
    'Install built test resources; requires root, installation directory and greeter state directory.',
  ),
  ScriptDefinition(
    'greetd-test/start.sh',
    ScriptKind.internal,
    'Run the installed copy through greetd-test start; requires root and an SDDM test installation.',
  ),
  ScriptDefinition(
    'greetd-test/restore.sh',
    ScriptKind.internal,
    'Run the installed copy through greetd-test restore; requires root and test recovery resources.',
  ),
  ScriptDefinition(
    'greetd-test/launch.sh',
    ScriptKind.internal,
    'Installed test greetd entrypoint; requires current-run and test resources.',
  ),
  ScriptDefinition(
    'greetd-test/display-layout.py',
    ScriptKind.tool,
    'Capture desktop layout or run an app with saved layout.',
  ),
  ScriptDefinition(
    'greetd-test/display_profile.py',
    ScriptKind.tool,
    'Resolve a display profile; requires --reference and --state.',
  ),
  ScriptDefinition(
    'greetd-test/screenshot.py',
    ScriptKind.internal,
    'Capture login outputs; requires Sway, grim and AKARI_LOG_DIR.',
  ),
];

List<ScriptDefinition> findRepositoryScripts(Directory repoRoot) {
  final root = Directory('${repoRoot.path}/scripts');
  final paths =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map((file) => file.path.substring(root.path.length + 1))
          .where((path) => path.endsWith('.sh') || path.endsWith('.py'))
          .toList()
        ..sort();
  return [for (final path in paths) getRepositoryScript(path)];
}

ScriptDefinition getRepositoryScript(String path) {
  for (final script in repositoryScripts) {
    if (script.path == path) return script;
  }
  throw FormatException('Unclassified repository script: $path');
}
