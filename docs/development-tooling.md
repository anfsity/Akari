# Development Tooling

Run project checks through the Dart tool entry point:

```sh
fvm dart run tool/mozais.dart build
fvm dart run tool/mozais.dart verify
fvm dart run tool/mozais.dart verify-perf
fvm dart run tool/mozais.dart generate-scenes
fvm dart run tool/mozais.dart trace-perf
```

`build` accepts a theme project with `--theme PATH`, defaulting to
`themes/default`. It resolves that project's dependencies, generates its scene
source, and builds a separate host project in the run directory. The host imports
only the selected theme and does not rewrite the platform catalog. Projects can
live outside the Mozais repository. See the
[theme project contract](theme-package.md).

Use `build --theme themes/default --preview` to compile and launch a Linux preview.
Preview uses demo login state and defaults to debug mode; normal builds use the
real backend and default to release mode. The command waits until the preview
window closes. It launches the compiled executable without Flutter hot reload.

`verify` analyzes the shared theme SDK, catalog, components, and every project
discovered under `themes/`. It also runs a theme project's Flutter tests when it
contains `*_test.dart` files under `test/`.

The `scripts/build.sh`, `scripts/verify.sh`, `scripts/verify-perf.sh`,
`scripts/generate-scenes.sh`,
and `scripts/trace-perf-builds.sh` commands remain as shell entry points for
existing workflows. They delegate to the Dart CLI. Shell scripts continue to
own toolchain setup and Linux session work such as private D-Bus and Sway.

Use `--format json` for a machine-readable report on stdout. Every run also
writes a report and event log beneath `build/tool/runs/<run-id>/`. Each command
step has separate stdout and stderr log files. A report can be written to a
chosen path with `--report PATH`.

Build reports list the generated host project, build directory, and Linux
executable. SDK commands use the repository's configured Flutter SDK even when
the selected theme project lives outside the repository. `MOZAIS_FLUTTER_BIN`
and `MOZAIS_DART_BIN` can override those binaries.

Run reports use schema version 1. They include the command, run status and
timing, generated artifact paths, and an ordered list of command steps with
their arguments, working directories, exit codes, timing, and log paths. The
`events.jsonl` file records run and step start and finish events. Child command
output stays in the per-step logs so JSON stdout remains parseable.

The performance gate runs three measurement cycles by default. Additional
cycles can be requested with `--cycles COUNT`, where `COUNT` must be at least
three. Each cycle writes its raw report into that run's artifact directory;
the aggregate report remains at `build/perf/scene_report.json`.
