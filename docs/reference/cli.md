---
title: CLI and development tooling
description: Command targets, accepted options, display profiles, and execution reports.
---

## Commands and targets

From the repository root, use `fvm dart run tool/akari.dart COMMAND`. After
[installing the launcher](#shell-launcher-and-completion), use `akari COMMAND`.

| Command | Purpose | Command-specific options |
| --- | --- | --- |
| `build` | Build a selected theme and production backend | `--theme`, `--jobs`, `--mode`, `--platform` |
| `preview` | Preview a theme with demo login state | `--theme`, `--jobs`, `--mode` |
| `run` | Run the greeter with a private D-Bus and backend | `--theme`, `--jobs`, `--mode`, `--backend` |
| `run sway` | Run that greeter inside nested or headless Sway | Run options plus `--display-profile`, `--resolution`, `--scale`, `--sway-backend` |
| `run studio` | Edit scenes with the selected compiled theme | `--theme`, `--jobs` |
| `verify` | Check shared code, backend, and theme projects | `--theme` |
| `generate-scenes` | Generate typed Dart from scene JSON | `--theme` |
| `verify-perf` / `perf` | Run the theme's declared performance gate | `--theme`, arguments after `--` |
| `trace-perf` / `trace` | Run the theme's declared performance trace | `--theme`, arguments after `--` |
| `install` | Install the repository-bound launcher and completion | `--shell`, `--prefix`, `--rc` |
| `completion` | Print a completion script | `--shell` |
| `greetd-test` | Manage standalone login testing | [Operation-specific options](../guides/greetd-testing.md) |

Build, preview, run targets, verification, scene generation, and performance
commands also accept `--format text|json`, `--report PATH`, and `--dry-run`.
Every command accepts `--help` (`-h`). `install`, `completion`, and the
`greetd-test` family use their own output and option contracts.

`run sway` and `run studio` are targets of `run`, so use
`akari run TARGET --help` to see their accepted options. Studio always runs in
debug mode without a backend; it does not accept `--mode` or `--backend`.
Its developing user guide remains in the repository's
[Studio notes](https://github.com/anfsity/Akari/blob/main/docs/internal/theme-studio.md).

Run project checks through the Dart tool entry point:

```sh
fvm dart run tool/akari.dart build
fvm dart run tool/akari.dart verify
fvm dart run tool/akari.dart verify-perf
fvm dart run tool/akari.dart generate-scenes
fvm dart run tool/akari.dart trace-perf
```

Use `-t`, `-m`, and `-j` for `--theme`, `--mode`, and `--jobs`.
`perf` aliases `verify-perf`, and `trace` aliases `trace-perf`.
Long options also accept `--name=value`. Mixing short and long spellings of
the same option is still a duplicate error. `COMMAND --help` lists only options
accepted by that command. Only performance commands accept arguments after `--`;
they pass them literally to the theme's runner.

```sh
fvm dart run tool/akari.dart build -t themes/default -m release -j 4
fvm dart run tool/akari.dart perf -t themes/default -- --cycles 5
```

## Shell launcher and completion

Install a repository-bound `akari` command and shell completion at user level:

```sh
fvm dart run tool/akari.dart install --shell zsh
# Or, for bash:
fvm dart run tool/akari.dart install --shell bash
```

The launcher is written to `~/.local/bin/akari` and completion support to
`~/.local/share/akari/`. Installation appends one source line to `.zshrc`
(respecting `ZDOTDIR`) or `.bashrc`; repeating installation does not duplicate it.
Open a new shell or source the printed environment script to activate it.
The launcher works from any directory, preserves relative argument paths, and
uses the repository SDK and its `AKARI_*_BIN` overrides. Its repository must
remain available at the installed path; reinstall after moving the repository.
`install --prefix PATH --rc PATH` selects installation and startup file locations.

Completion covers commands and aliases, command-specific long and short options,
enum values, and paths. It stops after `--`, where arguments belong to the theme.
The parser, help, and generated scripts share `tool/src/cli_definition.dart`.
Reinstall after changing that definition to refresh installed completion scripts.
For manual registration, `akari completion --shell zsh` or `--shell bash` prints
the corresponding script.

Use `akari greetd-test install`, `start`, `restore`, `status` and `logs` for
standalone login testing. This command family calls the installed test lifecycle
scripts directly and keeps diagnostics outside repository run reports. Only
installation needs repository build artifacts; status/log queries and service
control do not acquire theme locks or create development run directories.
The `akari` launcher still needs the repository and SDK. Emergency recovery
remains `sudo /opt/akari-test/restore.sh`, independent of both.
See [Standalone greetd testing](../guides/greetd-testing.md) for options and prerequisites.

## Build, preview, and run

`build` accepts a theme project with `--theme PATH`, defaulting to
`themes/default`. It resolves that project's dependencies, generates its scene
source, and builds a reusable host project under `build/tool/hosts/`. The host imports
only the selected theme. Projects can
live outside the Akari repository. See the
[theme project contract](theme-package.md).

Use `run --theme PATH` to start a complete greeter on a private D-Bus session.
It compiles and starts the Rust mock backend by default; `--backend real` selects
production transport. The frontend always uses D-Bus. `run` directly owns the
selected theme's Flutter session.

Use `preview --theme PATH` to preview the theme with frontend demo state.
Both commands default to debug mode and reload Dart and asset changes on save.
Scene JSON edits first run incremental code generation; failed generation keeps
the last working theme. `r` regenerates and reloads, `R` restarts, and `q` quits.
Profile/release sessions do not hot reload. Both commands accept `--jobs COUNT`.

Preview opens directly in the current desktop without a nested compositor. Preview defaults to a resizable, undecorated window. `run` and built
greeter bundles default to undecorated fullscreen. Set
`AKARI_WINDOW_MODE=fullscreen` for a fullscreen preview or `windowed` for a
windowed greeter. Exit live sessions with `q` in the launching terminal.

Fullscreen greeters render the same theme on every connected monitor, using
each output's logical size and scale. Account, session, authentication, dormant
state, and credential text are shared; keyboard actions belong to the focused
window. Connecting or disconnecting an output updates its window without
restarting authentication. Windowed previews use one window.

For native multi-monitor regression checks, build a demo preview bundle and run
`python3 test/support/multi_display_workflow_test.py --app PATH/greeter`.
This opt-in check requires Sway, wtype, and grim. It starts an isolated headless
compositor with mixed output scales, tests hotplug and both window modes, and
retains screenshots and logs in the printed temporary directory.

## Sway sessions and display profiles

For a step-by-step comparison and troubleshooting, see
[display testing](../guides/display-testing.md).

A preview on Hyprland inherits that output's scale. Use `run sway` to apply
the standalone greeter's scale in a nested compositor:

```sh
akari run sway
akari run sway --display-profile reference
akari run sway --display-profile login
akari run sway --resolution 1920x1080 --scale 1.6
akari run sway --display-profile reference --sway-backend headless
```

The selected theme, build mode, build jobs, mock/real backend and reload keys
follow `run`. `scripts/debug-sway.sh` forwards to this same CLI entry point.
The session requires Python 3, Sway, swaymsg and grim. The default Wayland backend
opens virtual outputs in the current Wayland desktop; headless needs no desktop.
Neither switches the display manager. The session owns its private D-Bus,
backend, compositor, frontend process group and temporary runtime directory.
Quitting or a failure cleans them up and retains logs.

`--display-profile` accepts `auto` (default), `login` and `reference`. Auto imports
the newest complete, marked DRM login snapshot from
`/opt/akari-test/current-run/greeter/session-*/`, or keeps a newer saved login
profile. Without one, it uses `config/sway/reference.json`: one output,
1920×1080 pixels, scale 1, logical viewport 1920×1080. `login` reports an error
when no valid login profile exists. `reference` bypasses login discovery and
import, allowing consistent team comparisons. Reinstall the greetd harness to
produce marked snapshots; older unmarked `outputs.json` files remain diagnostics.

Imported profiles live at
`${XDG_STATE_HOME:-~/.local/state}/akari/display-profiles/login.json`, with
atomic replacement and owner-only access. They retain mode including refresh,
scale, transform, logical rectangle, display identity, capture time, original
snapshot path and test/session provenance. Failed attempts, partial or corrupt
snapshots, and nested/headless outputs cannot replace a valid login record.
Raw login logs stay at their original paths; the saved profile remains usable
after those logs are removed. Dry-run resolves defaults without importing files
or creating run directories.

Resolution and scale come from one base profile before explicit overrides.
`--resolution WIDTHxHEIGHT` means reference output pixels; `--scale NUMBER`
is the intended standalone scale and must be positive. Headless outputs enforce
that resolution: at 1920×1080 and scale 1.6 the logical viewport is 1200×675.
On Hyprland, the outer compositor determines the actual output dimensions. Either
option can override a single output while preserving the other base values;
the complete resulting target is reported as customized. Multi-output profiles
reject these global overrides; select `reference` for a single-output override.
Multiple login displays map in top-to-bottom, then left-to-right order to
`WL-1`, `WL-2`, … or `HEADLESS-1`, `HEADLESS-2`, … while retaining each display's
reference mode, scale, transform and logical position. Reports keep their original names.

Startup prints the source, complete targets, actual outputs, and log/screenshot
locations. `--format json` includes this information in the run report's
`display` field. Sway artifacts live under `build/tool/runs/<run-id>/sway/`:
`display-report.json`, raw `outputs.json`, `sway.log`, `flutter.log`, generated
configuration and `screenshots/<virtual-output>.png`. Screenshots are taken
inside Sway after all greeter windows appear, at each output's own pixel scale.
Virtual backends choose refresh rates independently; reports retain physical
refresh as provenance. Fixed geometry verifies mode dimensions, scale, transform
and rect; Hyprland geometry verifies the settings described below.

On Hyprland, windows stay under the desktop's normal tiling and fullscreen
management. The session reads each owned window's monitor and applies
`inner scale = selected standalone scale / Hyprland monitor scale`. For example,
TTY scale 1 on a monitor with Hyprland scale 1.6 uses inner scale 0.625. When
fullscreen on the same monitor and physical mode, the logical viewport and
content size match standalone TTY Sway. Fullscreen dimensions come from the
monitor rather than the profile's reference resolution. Use your normal
Hyprland fullscreen key to compare with TTY.

Resizing, entering or leaving fullscreen updates the viewport without stopping
the theme. Moving the window to another monitor recalculates its scale. The
session only reads Hyprland IPC and changes its own inner Sway outputs; it
requires no floating rules, fixed window sizes, or desktop configuration edits.
Reports retain the original `target`, the compensated `effective_target`
(including host monitor and scale), and `actual`. `matched` checks the effective
output settings for compositor-managed geometry. Inner screenshots use the
adopted output's scale and dimensions, so they may differ in pixel dimensions
from TTY captures even when the displayed content size matches.

Headless sessions keep fixed-profile verification and fail on output drift.
Other outer compositors still require windows that accept the requested profile
sizes. Use headless for fixed-resolution screenshots. Nested/headless tests do
not replace DRM hardware or standalone TTY tests.

Run the native nested regression matrix against a built greeter and mock backend:

```sh
python3 test/support/sway_native_workflow_test.py \
  --app build/out/default/greeter \
  --backend backend/target/akari-mock/debug/backend
```

This creates an isolated headless outer Sway at scales 1 and 1.6, then tests
inner scales 1 and 1.6. It retains target/actual reports and checks 1920×1080
inner screenshot dimensions for all four combinations. It does not alter the
developer's desktop configuration or certify Hyprland-specific placement.

## Verification and generated hosts

Production `build` defaults to release and compiles both frontend and Rust backend.

`verify` analyzes shared code, the backend, and every project discovered under
`themes/`. With `--theme PATH`, it checks only the selected theme alongside shared
code and the backend. Theme-specific UI tests live in their theme package. It
also runs a theme project's Flutter tests when it contains `*_test.dart` files under `test/`.

The root project contains shared application code and repository tests. The CLI
generates the executable entrypoint for each selected theme. For repository
debugging, `tool/dev_main.dart` explicitly injects the default theme;
the CLI and Sway wrapper use the selected theme's generated host. To run the
repository entrypoint directly with demo login state after generating scenes:

```sh
fvm flutter run -d linux --target tool/dev_main.dart
```

Use the CLI for build, run, verification, scene generation, and performance
workflows. After installing the launcher, use `akari build`, `akari run`,
`akari verify`, `akari generate-scenes`, `akari perf`,
and `akari trace`.
Shell scripts handle toolchain setup and checks, standalone backend startup,
and Linux session work such as private D-Bus and Sway. `scripts/debug-dbus.sh`
accepts a command to run with the backend on a private bus; without a command,
it invokes the CLI's `run` command directly.

## Reports and build outputs

Use `--format json` for a machine-readable report on stdout. Every run also
writes a report and event log beneath `build/tool/runs/<run-id>/`. Each command
step has separate stdout and stderr log files. A report can be written to a
chosen path with `--report PATH`.

For commands using this report protocol, `--dry-run` prints a JSON execution
plan, including artifact paths, without running build or session steps. It does
not write the report or reserve its run directory. A Sway plan resolves the
selected display profile without importing it, but has no actual outputs or
screenshots because no compositor has started.

Build reports list the generated host project, build directory, and Linux
executable. SDK commands use the repository's configured Flutter SDK even when
the selected theme project lives outside the repository. `AKARI_FLUTTER_BIN`
and `AKARI_DART_BIN` can override those binaries.

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

## Theme performance commands

`verify-perf` and `trace-perf` select one theme with `--theme PATH`, defaulting
to `themes/default`. They execute that theme's explicitly declared perf command
after resolving its dependencies and generating its scenes. The CLI does not
supply interaction scripts, metric schemas, baselines, or pass/fail thresholds.
See the [theme perf protocol](theme-package.md#performance-protocol).

Arguments following `--` are passed literally to the theme command. For the
default theme, request five measurement cycles with:

```sh
fvm dart run tool/akari.dart verify-perf --theme themes/default -- --cycles 5
```

The default theme owns its Linux profile integration fixture, measurement and
trace tools, and baseline under `themes/default/perf/`. Its gate defaults to
three cycles, requires at least three, and accepts `--baseline PATH` after `--`.
The fallback theme currently declares no performance commands.

Each perf command receives an absolute `AKARI_PERF_OUTPUT_DIR` pointing to
`build/tool/runs/<run-id>/perf/`. Successful commands must publish `result.json`;
the run report records its validated artifact paths in `theme_artifacts` without
parsing the artifact contents. Failed commands can publish diagnostic artifacts
too. Their nonzero exit codes are preserved, and missing failure manifests do
not hide the command failure. Protocol errors fail the run while retaining its
logs and report. JSON console output remains a single CLI report.

## Caches and parallel work

Host projects retain Flutter and native build caches between runs. Shared application
source is linked into the host, and Linux runner files are synchronized only when
they change. Run directories contain logs and reports rather than another build.
Host synchronization and build-link publication run inside the CLI process to
avoid extra Dart VM startups. Their plan/report entries retain the equivalent
standalone command and include `in_process: true`; failures still produce step
logs and stop dependent steps.
After resolving host dependencies, builds and sessions pass `--no-pub` to
Flutter to avoid repeating that check. The reload controller loads only SDK
resolution and session code to reduce its startup work.

Production builds also compile the Rust backend. Backend compilation runs alongside
theme preparation. `build --jobs COUNT` limits Cargo tasks and native C++ compile/link
jobs through a CMake Ninja pool. Without it, each tool uses its normal multicore default.
This does not set the Dart compiler's thread count.

Rust mock and production builds use separate stable target directories beneath
`backend/target/akari-mock/` and `backend/target/akari-real/`. Commands sharing a
theme serialize on a process lock; different themes can build independently.
