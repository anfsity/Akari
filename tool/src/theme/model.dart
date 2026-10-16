enum BuildMode {
  debug,
  profile,
  release;

  String get rustProfile => this == debug ? 'debug' : 'release';
}

enum BackendMode { mock, real }

enum ThemeHostKind {
  greeter('real'),
  preview('demo'),
  studio('studio');

  const ThemeHostKind(this.cacheName);
  final String cacheName;

  String get backendDefine => this == greeter ? 'real' : 'demo';
}

enum ThemeRunTarget {
  greeter('run', 'run', ThemeHostKind.greeter),
  sway('run sway', 'sway', ThemeHostKind.greeter),
  studio('run studio', 'studio', ThemeHostKind.studio);

  const ThemeRunTarget(this.commandName, this.stepName, this.hostKind);
  final String commandName;
  final String stepName;
  final ThemeHostKind hostKind;
}

enum SwayBackend { wayland, headless }
