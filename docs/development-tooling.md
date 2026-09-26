# Development Tooling

Run project checks through the Dart tool entry point:

```sh
fvm dart run tool/mozais.dart build
fvm dart run tool/mozais.dart verify
fvm dart run tool/mozais.dart verify-perf
fvm dart run tool/mozais.dart generate-scenes
fvm dart run tool/mozais.dart trace-perf
```

`build` is the theme composition entry point. It discovers every local
`mozais_theme_*` package, regenerates the catalog and scene sources, resolves
package dependencies, and builds the Linux Flutter application. A new theme
package only needs to follow the [theme package contract](theme-package.md).

`verify` analyzes the shared theme SDK, catalog, components, and every discovered
theme package. It also runs a theme package's Flutter tests when that package
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

Run reports use schema version 1. They include the command, run status and
timing, generated artifact paths, and an ordered list of command steps with
their arguments, working directories, exit codes, timing, and log paths. The
`events.jsonl` file records run and step start and finish events. Child command
output stays in the per-step logs so JSON stdout remains parseable.

The performance gate runs three measurement cycles by default. Additional
cycles can be requested with `--cycles COUNT`, where `COUNT` must be at least
three. Each cycle writes its raw report into that run's artifact directory;
the aggregate report remains at `build/perf/scene_report.json`.
