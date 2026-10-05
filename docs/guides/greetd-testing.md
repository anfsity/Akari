---
title: Standalone greetd testing
description: Build and install the real-login harness, capture displays, inspect logs, and restore SDDM.
---

The maintained test harness lives in `scripts/greetd-test/` and installs into
`/opt/akari-test`. It uses the production backend: authentication talks to greetd
and power actions call logind, performing actual suspend, reboot and shutdown.
Boot configuration stays on SDDM. Desktop development with `akari run` still
uses mock authentication and mock power by default.

Install the repository-bound `akari` launcher as described in
[Development Tooling](../reference/cli.md). `akari greetd-test --help` lists
all operations; each operation has its own help and bash/zsh completion.
Install, start and restore request sudo when needed. Status and ordinary log
reading do not request elevated privileges.

Build and install while no previous test or timer is active:

```sh
akari greetd-test install
```

The installer first builds the current repository's default theme and production
backend in Linux release mode with four build jobs. It runs the build as the sudo
caller (or the repository owner when invoked directly as root), keeping SDK and
repository caches owned by that user. SDK selection uses the same repository
configuration and `AKARI_FLUTTER_BIN` / `AKARI_DART_BIN` overrides as the CLI.
A failed build aborts installation before any installed files or backups change.

After a successful build, installation backs up the previous frontend, backend,
scripts and configuration beneath `/opt/akari-test/backups/`. It does not switch
display managers.
The installer expects the existing test setup's `greeter` account and writable
`/opt/akari-test/state` directory.

Installation also captures the active Sway or Hyprland desktop's display order
in `/opt/akari-test/display-layout.json`. An aligned horizontal row or vertical
column is supported. This uses the desktop's configured arrangement; display
hardware cannot report which side of another screen it physically occupies.
Login computes contiguous positions from Sway's actual logical output sizes,
retaining the login environment's own modes and scale. Hotplug recomputes those
positions; newly discovered outputs follow the saved outputs until installation
captures a new arrangement. If no supported desktop layout can be captured,
installation preserves the previous layout, or uses Sway's automatic arrangement
when no layout has been saved. Reinstall from the desktop after rearranging screens.

Save work, log out of the desktop, log in on tty3, then run:

```sh
akari greetd-test start
```

Preflight uses `SUDO_TTY` to identify the original terminal even when sudo creates
a PTY. It rejects live graphical user sessions, ignores sessions already closing,
checks SDDM boot configuration, and records diagnostics before changing services.
Recovery is armed before SDDM stops. A failed setup restores it immediately;
systemd's `ExecStopPost` restores it when the test service exits; an independent
ten-minute timer remains the fallback while the service is running. A successful
login exits the greeter, while greetd continues to own the user desktop session.

To restore manually, switch to tty3 and run:

```sh
akari greetd-test restore
```

Recovery itself is independent of this CLI. systemd's timer and exit callback
always invoke `/opt/akari-test/restore.sh` directly. If the repository or
Flutter/Dart SDK is unavailable, restore from tty3 with:

```sh
sudo /opt/akari-test/restore.sh
```

The CLI, timer and exit callback all use this single recovery implementation.
`install`, `start` and `restore` accept `--dry-run` to print the command that would
run without requesting sudo or changing files. Preflight still runs during an
actual start. The CLI does not change the TTY or live-desktop requirements.

Inspect installed artifacts, SDDM, the test service, the recovery timer and saved
log paths with:

```sh
akari greetd-test status
akari greetd-test status --format json
```

Logs live outside `/opt`, under `/var/tmp/akari-greetd-test-<caller-uid>/`.
For a user with UID 1000 this is `/var/tmp/akari-greetd-test-1000/`.
All users can read startup, frontend, backend, compositor and recovery logs
directly, including while the test is running, without sudo or special group
membership. Direct root invocation uses UID 0 and keeps the same read access.
Log directories use mode `0755`; log files use mode `0644`. Only their owners
and root can write to them.

Each startup attempt that reaches log setup gets its own
`<timestamp>-<pid>/start.log`. Startup prints its log directory before preflight.
The `latest` symlink points to the latest attempt, including preflight failures.
The `current` symlink points to the latest armed test. The installation keeps
a `current-run` pointer to that directory for launching and recovery, so a
later rejected attempt cannot redirect recovery logs. Restore prints the test's
log directory too.

Each greeter launch retains `backend.log`, `flutter.log`, `sway.log`,
`lifecycle.log` and `outputs.json` under its own `greeter/session-*/` directory;
returning from the desktop does not overwrite earlier logs. Recovery saves the
test and SDDM journal plus its own timestamp/result.

After initial output arrangement, the launch also publishes `display-profile.json`
with normalized active outputs, DRM login provenance, run/session paths, capture
time and a checksum of the original `outputs.json`. Publication is atomic and
follows the raw snapshot. This is the startup state; hotplug keeps rearranging
outputs but does not update this snapshot. Re-run the test to capture a changed
display combination. Sessions without a saved arrangement use Sway's initial
positions and the same snapshot capture path.

Back on the desktop, `akari run sway` automatically imports the newest valid
marked snapshot into the developer's local state. It ignores incomplete,
damaged or unmarked captures and keeps any existing valid local profile.
`--display-profile reference` uses the project's 1920×1080, scale 1
reference (fixed resolution for headless); `--display-profile login` requires
a valid login capture.
See [Development Tooling](../reference/cli.md) for overrides, multi-output
mapping, actual-output checks and inner screenshots. Reinstall the harness to
enable these source-marked captures; login processes never write to a
developer's home directory.

Continue with [display testing](display-testing.md#compare-a-nested-session-with-standalone-login)
to compare that capture in a desktop session or produce fixed-resolution images.

Inspect the latest startup attempt or the test used by recovery:

```sh
akari greetd-test logs
akari greetd-test logs --run current --file backend -n 100
akari greetd-test logs --run current --file flutter --follow
```

`logs` defaults to the caller's latest startup attempt and its `start.log`.
`--run current` selects the last armed test, even after restoration. `--file`
accepts `start`, `backend`, `flutter`, `sway`, `lifecycle`, `restore` and `journal`.
Greeter logs select the newest session; older session files remain at the saved
run path. `--lines` (`-n`) defaults to 100; `--follow` (`-f`) follows the selected
file, including its later creation. It does not switch sessions automatically.

Set a custom location when starting a test (relative paths use the invocation
directory):

```sh
akari greetd-test start --log-dir /var/tmp/my-akari-test
```

The greeter must be able to traverse the parent directories of a custom location;
startup checks access before stopping SDDM. `logs` discovers the saved location
without needing `--log-dir` again. A private home directory usually
prevents this, so use a location beneath `/var/tmp`. The installation also retains
a per-caller `latest-run-<uid>` pointer, including failed preflight attempts. Recovery resolves the saved `current-run` pointer
automatically and does not require the custom setting again. Each prepared test
saves its scale and log root in `config.json`. The former `AKARI_TEST_SCALE`
and `AKARI_TEST_LOG_DIR` settings are replaced by these explicit start options.

For live system service output, use `sudo journalctl -u akari-test.service -f`;
the directly readable `journal.log` is saved during recovery. Reinstall the
scripts to make these changes available in `/opt/akari-test`. Existing logs in
the old `/opt/akari-test/test-runs/` directory remain there.

The standalone login environment supplies the local visual reference. Its output scale
remains 1 by default. `akari greetd-test start --scale NUMBER` explicitly
overrides it; Sway records the actual output mode and scale in `outputs.json`.
`akari run sway` compensates for the outer Hyprland monitor scale, so a
fullscreen nested window on the same monitor and mode has the same logical
viewport and content size as TTY. The inner scale is the selected login scale
divided by the Hyprland monitor scale; monitor settings remain untouched.
Headless tests reproduce the selected profile's fixed resolution and scale.

Validate harness control flow without root or live system changes:

```sh
python3 test/support/greetd_test_workflow_test.py
python3 test/support/display_profile_test.py
python3 test/support/display_layout_test.py
python3 test/support/sway_session_test.py
```
