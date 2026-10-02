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
source, and builds a reusable host project under `build/tool/hosts/`. The host imports
only the selected theme. Projects can
live outside the Mozais repository. See the
[theme project contract](theme-package.md).

Use `run --theme PATH` to start a complete greeter on a private D-Bus session.
It compiles and starts the Rust mock backend by default; `--backend real` selects
production transport. The frontend always uses D-Bus. `run` directly owns the
selected theme's Flutter session and never invokes `debug-ui.sh`.

Use `preview --theme PATH` to preview the theme with frontend demo state.
Both commands default to debug mode and reload Dart and asset changes on save.
Scene JSON edits first run incremental code generation; failed generation keeps
the last working theme. `r` regenerates and reloads, `R` restarts, and `q` quits.
Profile/release sessions do not hot reload. Both commands accept `--jobs COUNT`.
Production `build` defaults to release and compiles both frontend and Rust backend.

`verify` analyzes shared code, the backend, and every project discovered under
`themes/`. With `--theme PATH`, it checks only the selected theme alongside shared
code and the backend. Theme-specific UI tests live in their theme package. It
also runs a theme project's Flutter tests when it contains `*_test.dart` files under `test/`.

The root project contains shared application code and repository tests. The CLI
generates the executable entrypoint for each selected theme. For repository
debugging, `tool/dev_main.dart` explicitly injects the default theme;
`scripts/debug-sway.sh` uses this entrypoint. `scripts/debug-ui.sh` delegates to
`run` and accepts the same CLI options. To run it
directly with demo login state after generating scenes:

```sh
fvm flutter run -d linux --target tool/dev_main.dart
```

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

Successful Linux builds publish relative symlinks at `build/out/<theme-name>`
(the entire frontend bundle) and `build/out/backend` (the production backend).
For example, run `build/out/default/greeter` or `build/out/backend`.
The report records `bundle_link` and `backend_link` and text output prints these
short paths. Links update only after both builds succeed. They point into build
caches, so rebuilding can change their contents and cleaning caches breaks them;
they do not preserve a previous successful build. The backend link follows the
latest successful build. A frontend link cannot be claimed by another project
with the same theme name; remove that link explicitly to switch projects.
The theme name `backend` is reserved for the backend output link.

Run reports use schema version 1. They include the command, run status and
timing, generated artifact paths, and an ordered list of command steps with
their arguments, working directories, exit codes, timing, and log paths. The
`events.jsonl` file records run and step start and finish events. Child command
output stays in the per-step logs so JSON stdout remains parseable.

`verify-perf` and `trace-perf` select one theme with `--theme PATH`, defaulting
to `themes/default`. They execute that theme's explicitly declared perf command
after resolving its dependencies and generating its scenes. The CLI does not
supply interaction scripts, metric schemas, baselines, or pass/fail thresholds.
See the [theme perf protocol](theme-package.md#performance-protocol).

Arguments following `--` are passed literally to the theme command. For the
default theme, request five measurement cycles with:

```sh
fvm dart run tool/mozais.dart verify-perf --theme themes/default -- --cycles 5
```

The default theme owns its Linux profile integration fixture, measurement and
trace tools, and baseline under `themes/default/perf/`. Its gate defaults to
three cycles, requires at least three, and accepts `--baseline PATH` after `--`.
The fallback theme currently declares no performance commands.

Each perf command receives an absolute `MOZAIS_PERF_OUTPUT_DIR` pointing to
`build/tool/runs/<run-id>/perf/`. Successful commands must publish `result.json`;
the run report records its validated artifact paths in `theme_artifacts` without
parsing the artifact contents. Failed commands can publish diagnostic artifacts
too. Their nonzero exit codes are preserved, and missing failure manifests do
not hide the command failure. Protocol errors fail the run while retaining its
logs and report. JSON console output remains a single CLI report.

Host projects retain Flutter and native build caches between runs. Shared application
source is linked into the host, and Linux runner files are synchronized only when
they change. Run directories contain logs and reports rather than another build.

Production builds also compile the Rust backend. Backend compilation runs alongside
theme preparation. `build --jobs COUNT` limits Cargo tasks and native C++ compile/link
jobs through a CMake Ninja pool. Without it, each tool uses its normal multicore default.
This does not set the Dart compiler's thread count.

Rust mock and production builds use separate stable target directories beneath
`backend/target/mozais-mock/` and `backend/target/mozais-real/`. Commands sharing a
theme serialize on a process lock; different themes can build independently.
