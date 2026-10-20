---
title: CLI and development tooling
description: Command targets, accepted options, display profiles, and execution reports.
---

## Commands and targets

Run commands from the repository root with `fvm dart run tool/akari.dart COMMAND`, or install the [shell launcher](#shell-launcher-and-completion) and use `akari COMMAND`.

| Command | Purpose | Command-specific options |
| --- | --- | --- |
| `build` | Build a selected theme, production backend, and native splash | `--theme` (`-t`), `--jobs` (`-j`), `--mode` (`-m`), `--platform` |
| `preview` | Run automated login UI journeys in one window and exit | `--theme`, `--jobs`, `--scenario` |
| `run` | Start the greeter with a private D-Bus and backend | `--theme`, `--jobs`, `--mode`, `--backend` |
| `run sway` | Run the greeter inside nested or headless Sway | `run` options + `--display-profile`, `--resolution`, `--scale`, `--sway-backend` |
| `run splash` | Preview the native loading animation until closed | `--jobs`, `--mode`, `--light` |
| `run studio` | Edit scenes visually with the selected compiled theme | `--theme`, `--jobs` |
| `verify` | Run analyzer, Rust checks, and tests across packages and themes | `--theme` |
| `generate-scenes` | Generate typed Dart (`*.scene.g.dart`) from scene JSON | `--theme` |
| `verify-perf` (`perf`) | Execute the theme's declared performance gate | `--theme`, arguments after `--` |
| `trace-perf` (`trace`) | Execute the theme's declared performance trace | `--theme`, arguments after `--` |
| `install` | Build and deploy the production login environment | `--theme`, `--jobs`, `--keyring`, `--dry-run` |
| `install cli` | Install the repository-bound `akari` launcher and completion | `--shell`, `--prefix`, `--rc` |
| `uninstall` | Remove production (`login`), `test`, or `all` installations | `--scope`, `--dry-run` |
| `login enable` / `disable` | Enable Akari for next boot or restore the prior display manager | `--dry-run` |
| `login rollback` | Switch between `current` and `previous` deployed releases | `--dry-run` |
| `login configure-keyring` | Configure greetd keyring PAM hooks without rebuilding | `--keyring`, `--dry-run` |
| `login enable-gaze` / `disable-gaze` | Enable Gaze face auth on stock Arch greetd or restore password stack | `--dry-run` |
| `login status` | Inspect deployment and systemd service state | `--format` |
| `login logs` | Read the service journal or latest greeter session logs | `--component`, `--lines` (`-n`), `--follow` (`-f`) |
| `toolchain check` / `setup` | Verify or initialize development dependencies | `--dry-run` |
| `docs build-api` / `verify` | Generate Dart API docs or verify a built handbook directory | `--dry-run`, site path after `--` for `verify` |
| `script list` / `run` | List or invoke repository helper scripts | `list --format`, `run SCRIPT --dry-run -- args` |
| `completion` | Print a shell completion script | `--shell` |
| `greetd-test` | Manage standalone TTY login testing | See [Standalone greetd testing](../guides/greetd-testing.md) |

### Shared flags & conventions

- **Report & dry-run flags**: `build`, `preview`, `run*`, `verify`, `generate-scenes`, and `*-perf` accept `--format text|json`, `--report PATH`, and `--dry-run`.
- **Short options**: `-t` (`--theme`), `-m` (`--mode`), and `-j` (`--jobs`). Do not mix short and long forms of the same flag in one call.
- **Pass-through arguments**: `perf`, `trace`, `script run`, and `docs verify` forward arguments after `--` verbatim.
- **Theme Studio notes**: `akari run studio` always runs in debug mode without a backend (`--mode` and `--backend` are not accepted). See the internal [Theme Studio guide](https://github.com/anfsity/Akari/blob/main/docs/internal/theme-studio.md).

## Production login installation

Deploy Akari as a systemd display manager on Linux hosts with `systemd`, `/usr/bin/greetd`, `/usr/bin/sway`, `python3`, `swaymsg`, `swaybg`, `dbus-daemon`, `busctl`, `setpriv`, and `accountsservice`:

```sh
akari install --theme themes/default --jobs 4
akari login enable
akari login status
```

### Deployment layout

| Path / Resource | Purpose |
| --- | --- |
| `akari-greeter` | Dedicated unprivileged system account running the greeter |
| `/opt/akari/releases/` | Versioned release bundles with `current` and `previous` symlinks |
| `/etc/akari/greetd.toml` & `sway.conf` | Isolated Akari configuration (leaves `/etc/greetd/config.toml` untouched) |
| `/etc/akari/display-layout.json` | Monitor order captured from your active Sway/Hyprland desktop on first install |
| `/var/lib/akari/greeter/` | Persistent account/session preferences |
| `/var/log/akari/greeter/session-*/` | Per-launch `backend.log`, `flutter.log`, and `sway.log` (readable without `sudo`) |

### Keyring & PAM configuration

`akari install` configures `/etc/pam.d/greetd` (backing up the original to `/var/lib/akari/greetd.pam.before-keyring`):

- `--keyring auto` (default): Detects installed `pam_gnome_keyring.so` and `pam_kwallet5.so` modules (or prompts to install on Arch, Debian/Ubuntu, and Fedora).
- `--keyring gnome` / `--keyring kwallet`: Configure only the specified provider (`use_authtok` + `auto_start` for GNOME Keyring; `auto_start force_run` for KWallet).
- `--keyring none`: Remove Akari's managed keyring PAM block while preserving other edits.
- Update keyring PAM rules on an existing installation without rebuilding:
  ```sh
  akari login configure-keyring --keyring gnome
  ```
- Enable or remove Gaze facial authentication on Arch Linux with `akari login enable-gaze` and `akari login disable-gaze` (see [Gaze setup](../guides/greetd-testing.md#connect-greetd-on-arch)).

### Service management, logs, and uninstall

```sh
# Read service journal or component logs (backend, flutter, sway)
akari login logs
akari login logs --component backend --lines 200
akari login logs --component flutter --follow

# Switch back to the previous release or prior display manager
akari login rollback
akari login disable

# Remove installations (--scope login | test | all)
akari uninstall --scope all --dry-run
akari uninstall
```

:::tip[Emergency TTY recovery]
`login enable` and `login disable` update boot symlinks without stopping your active desktop. If you need to disable Akari from a TTY without the repository or Dart SDK, run:
```sh
sudo python3 /opt/akari/manage.py disable
```
Then reboot to return to your previous display manager.
:::

## Shell launcher and completion

Install the user-level `akari` wrapper (`~/.local/bin/akari`) and completion scripts (`~/.local/share/akari/`):

```sh
fvm dart run tool/akari.dart install cli --shell zsh
# Or for bash:
fvm dart run tool/akari.dart install cli --shell bash
```

- Use `--prefix PATH` and `--rc PATH` to customize installation locations.
- Re-run `install cli` if you move the repository or update CLI option definitions in `tool/src/cli/definition.dart`.
- Print raw completion scripts manually with `akari completion --shell zsh|bash`.

## Repository scripts

Discover and run helper scripts under `scripts/` with the repository root as working directory:

```sh
akari script list
akari script list --format json
akari script run run-backend.sh -- --help
akari script run greetd-test/display-layout.py -- capture
```

## Build, preview, and run

- **`build`**: Resolves dependencies, generates scene code, builds the reusable Flutter host under `build/tool/hosts/`, and compiles the release bundle + production Rust backend.
- **`run`**: Starts the Flutter greeter and Rust mock backend (`--backend real` for production transport) on a private D-Bus session. Supports hot reload on Dart/asset/JSON saves. Fullscreen by default (`AKARI_WINDOW_MODE=windowed` for a window).
- **`preview`**: Runs `face-success` and `password-fallback` (or `--scenario NAME`) once in an undecorated window using controlled frontend events and exits.
- **`run splash`**: Opens a standalone preview window of the native loading screen until closed.

## Sway sessions and display profiles

Reproduce standalone greeter scaling inside a nested or headless Sway compositor:

```sh
akari run sway
akari run sway --display-profile reference
akari run sway --display-profile login
akari run sway --resolution 1920x1080 --scale 1.6
akari run sway --display-profile reference --sway-backend headless
```

### Display profile modes (`--display-profile`)

| Profile | Behavior |
| --- | --- |
| `auto` (default) | Imports the newest marked DRM snapshot from `/opt/akari-test/current-run/greeter/session-*/` into `${XDG_STATE_HOME:-~/.local/state}/akari/display-profiles/login.json`, or falls back to `reference`. |
| `login` | Requires a valid imported or newly captured TTY login profile; fails if none exists. |
| `reference` | Uses `config/sway/reference.json` (`1920x1080`, scale `1.0`), ignoring saved login captures. Required when overriding `--resolution` or `--scale` on a multi-monitor setup. |

### Output verification & Hyprland compensation

- **Artifacts**: Saved under `build/tool/runs/<run-id>/sway/`, including `display-report.json`, `outputs.json`, `sway.log`, `flutter.log`, and initial per-output PNGs under `screenshots/`.
- **Hyprland scale compensation**: On Hyprland, `run sway` reads the host monitor's scale and sets `inner_scale = target_login_scale / hyprland_monitor_scale`. When fullscreened on the same monitor, the logical viewport matches standalone TTY Sway.
- **Headless verification**: `--sway-backend headless` enforces fixed output dimensions and fails if actual Sway outputs drift from the requested target.

For step-by-step usage, see [Test displays and scaling](../guides/display-testing.md).

## Verification and generated hosts

`akari verify` checks shared packages, the Rust backend, Theme Studio, and all themes under `themes/` (or a single theme with `--theme PATH`).

For direct IDE debugging without the CLI host generator, `tool/dev_main.dart` injects the default theme into the root project:

```sh
fvm dart run tool/akari.dart generate-scenes --theme themes/default
fvm flutter run -d linux --target tool/dev_main.dart
```

## Reports and build outputs

- **Run reports**: Every CLI run writes `report.json` (schema v1), `events.jsonl`, and per-step stdout/stderr logs under `build/tool/runs/<run-id>/`. Use `--format json` to print the report to stdout or `--report PATH` to copy it to a custom file.
- **Dry runs**: `--dry-run` outputs the planned step graph and artifact paths as JSON without executing commands or creating run directories.
- **Build symlinks**: Successful Linux builds create relative symlinks at `build/out/<theme-name>` and `build/out/backend` pointing into the active build cache.

## Theme performance commands

```sh
fvm dart run tool/akari.dart verify-perf --theme themes/default -- --cycles 5
fvm dart run tool/akari.dart trace-perf --theme themes/default
```

`verify-perf` (`perf`) and `trace-perf` (`trace`) run the commands declared in the selected theme's `pubspec.yaml` `perf:` block and validate `result.json` inside `AKARI_PERF_OUTPUT_DIR` (`build/tool/runs/<run-id>/perf/`). See the [Performance protocol](theme-package.md#performance-protocol).

## Caches and parallel work

- **Host reuse**: Generated hosts under `build/tool/hosts/` retain Flutter and CMake caches across runs and pass `--no-pub` after resolving dependencies.
- **Parallel jobs (`--jobs COUNT`)**: Bounds Cargo build tasks and CMake/Ninja C++ compile/link pools while building the Rust backend and Flutter frontend in parallel.
- **Target isolation**: Mock and real Rust builds use separate directories (`backend/target/akari-mock/` and `backend/target/akari-real/`), and per-theme locks allow different themes to build in parallel.
