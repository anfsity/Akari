---
title: Standalone greetd testing
description: Build and install the real-login harness, capture displays, inspect logs, and restore SDDM.
---

The maintained test harness lives in `scripts/greetd-test/` and installs into
`/opt/akari-test`. It uses the production backend: authentication talks to greetd
and power actions call logind, performing actual suspend, reboot and shutdown.
Boot configuration stays on SDDM. Desktop development with `akari run` still
uses mock authentication and mock power by default.

## User session environment

Production and harness greetd configurations enable profile loading. greetd
loads `/etc/profile` and `~/.profile`, then Akari forwards the authenticated
user's command to `$SHELL` in non-interactive login mode. The shell loads its
native configuration; Akari does not choose files or branch on shell names.
bash, sh, zsh, and fish are covered by native-shell integration tests.

Put exported desktop variables in login configuration, such as zsh's `.zprofile`
or fish configuration outside `status is-interactive`. `.zshrc` is not loaded.
POSIX profiles may be read again by the native shell's startup files, so keep
them safe to evaluate repeatedly. Install preserves existing configuration;
remove `source_profile = false` from `/etc/akari/greetd.toml` when upgrading an
older installation, or set it to `true`. Reinstall the harness to update its
configuration and backend together.

The user-side executor preserves arguments, supplies `LANG=C.UTF-8` only when
LANG is absent or empty, and logs locale diagnostics without replacing explicit
locale overrides. Desktop stdout/stderr and startup details go into private
`session-*.log` files under
`${XDG_STATE_HOME:-$HOME/.local/state}/akari/sessions/`. Before entering the native
login shell, Akari captures its stdout/stderr in a private `startup-*.log` in
the same directory, resolved from the environment before native shell startup.
If the shell changes `XDG_STATE_HOME`, the desktop log uses the updated location
while the startup log stays in the original location. greetd's own profile
loading and PAM output precede this launcher and are outside its redirection.
Greeter launch and shutdown diagnostics go to each greeter's `lifecycle.log`.

The ASCII handoff experiment prepares an AKARI wordmark before Sway exits and
animates a light sweep while the user session starts on a text-mode Linux VT.
It stops when graphics mode takes over, the session exits, or 15 seconds elapse,
then clears the VT buffer and scrollback so the last frame does not reappear
when the desktop exits.
PTYs and missing controlling terminals skip this behavior. Preview it with
`python3 scripts/ascii-transition.py preview`; see the
[handoff experiment](../proposals/login-handoff.md) for lifecycle and hardware
checks. Real VT testing must establish whether Sway/greetd preserves the prepared
buffer, including desktop startup failure, logout and VT switching.

Desktop and systemd service readiness belongs to the selected desktop/session
manager. UWSM-managed selections retain UWSM's environment and cleanup behavior.
Direct compositor sessions keep their existing integration; an additional
custom rice callback cannot order applications already launched by upstream.
Validate a compositor child, a newly started user service, and a newly activated
D-Bus service separately. A successful greetd handoff is not desktop readiness.

## Facial authentication

Akari starts authentication when the greeter wakes with an account and session
selected. A face provider's PAM messages stay visible during recognition;
successful PAM authentication starts the selected desktop without a password
submission. If the PAM stack proceeds to a password prompt after a timeout or
missing camera, the field returns with keyboard focus in the same attempt.

Use [Gaze](https://github.com/GunduLabs/gaze) as the initial face provider. Its
default sequential PAM mode tries face authentication before falling back to
the existing password rules. Akari displays PAM instructions without guessing
the provider from their wording; translated messages work the same way.
Camera configuration, enrollment, recognition timeouts and fallback policy belong
to the provider and PAM. Akari does not capture camera frames or store face models.
Preview and mock mode do not perform facial recognition.

### Install and verify Gaze

Follow Gaze's [installation guide](https://gaze.gundulabs.com/guide/installation.html).
On Arch, the facial authentication package is `gaze-bin`; the unrelated AUR
package named `gaze` is a file watcher. The base package provides the daemon,
CLI and PAM module; a desktop extension is not needed for Akari.

The Arch package's installation hooks also configure sudo and polkit. For a
greetd-only trial, create `/etc/gaze/pam-sudo.optout` before installing, back up
the existing polkit policy (including whether `/etc/pam.d/polkit-1` exists),
and restore that policy after installation. Review those hooks again on upgrades.
See Gaze's [PAM guide](https://gaze.gundulabs.com/guide/pam.html).

```sh
sudo install -d -m 0755 /etc/gaze
sudo touch /etc/gaze/pam-sudo.optout
yay -S --needed gaze-bin
sudo systemctl enable --now gazed
gaze config
```

Start with CPU inference, `security.level = "medium"` and liveness enabled.
Choose the RGB camera first; add IR after verifying its capture and emitter.
For multiple cameras, prefer a `usb:VVVV:PPPP` identifier over a numbered
`/dev/video*` path. Gaze captures the hardware directly, so recognition at the
login screen does not depend on a user's PipeWire session. See the
[configuration guide](https://gaze.gundulabs.com/guide/configuration.html).

Run enrollment from the desktop as the actual login account:

```sh
gaze add-face default
gaze auth --verbose
gaze doctor
```

These commands request administrator authentication where needed. `gaze auth`
tests the camera and recognition, but does not exercise greetd's PAM policy.
Before connecting PAM, verify successful recognition here. Keep an authenticated
administrator terminal available while editing PAM and back up the original
policy.

### Connect greetd on Arch

For the stock Arch stack where `/etc/pam.d/greetd` includes
`system-local-login`, create `/etc/pam.d/akari-gaze` with:

```text
#%PAM-1.0
auth       requisite                    pam_shells.so
auth       requisite                    pam_faillock.so preauth
auth       [success=ignore default=3]    pam_gaze.so
auth       requisite                    pam_env.so
auth       requisite                    pam_faillock.so authsucc
auth       sufficient                   pam_permit.so
auth       include                      system-local-login
```

Then replace the initial `auth` rules in `/etc/pam.d/greetd` with:

```text
auth       required     pam_securetty.so
auth       requisite    pam_nologin.so
auth       substack     akari-gaze
```

Keep the existing `account`, `session` and keyring rules. The helper checks
shell eligibility and lockout before Gaze. A face match loads the environment,
clears prior authentication failures and completes only the substack. Failure
or an unavailable Gaze module skips those three face-success rules and reaches
the existing password stack. Password failure ends the substack without
clearing the failed-attempt records. The parent stack still runs its keyring
auth rules; an ordinary `sufficient` rule in the parent would skip them.

Use `substack` in the parent: `include` expands its rules into that stack, so a
successful `sufficient` rule would end the parent's authentication too. The
numeric jump in the helper covers three ordinary module rules, not an include.
Review it when changing the helper. For a different PAM layout, follow the
distribution's policy and Gaze's
[greetd guide](https://gaze.gundulabs.com/guide/greetd.html) instead of copying
these rules.

The initial setup leaves TPM-backed password storage disabled. A face login
does not unlock a password-protected keyring automatically; unlock it in the
desktop when requested. Gaze's optional keyring integration is a separate setup
with additional storage and PAM requirements described in its greetd guide.

### Verify real login

Use the standalone harness below after installing the current Akari build.
Verify face success without password submission, an unsuccessful scan followed
by password login, and password fallback with the camera unavailable. Also
change the selected account during a scan and confirm the previous attempt
cannot start a session. A locked-out account must remain denied even when its
face matches. Inspect backend logs and `journalctl -u gazed -b` for failures.
Restore the backed-up greetd policy and remove `/etc/pam.d/akari-gaze` to remove
the trial integration.

## Install and run the harness

Install the repository-bound `akari` launcher as described in
[Development Tooling](../reference/cli.md). `akari greetd-test --help` lists
all operations; each operation has its own help and bash/zsh completion.
Install, start and restore request sudo when needed. Status and ordinary log
reading do not request elevated privileges.

Build and install while no previous test or timer is active:

```sh
akari greetd-test install
akari greetd-test install --theme themes/preset1
```

Select a theme project with `--theme PATH` (or `-t PATH`); the default is
the current repository's `themes/default`. Relative paths use the invocation
directory, and projects outside the repository are supported. `start` uses the
installed theme; change it by running `install` again with the desired project.

The installer first builds the selected theme and production backend in Linux
release mode with four build jobs. It runs the build as the sudo
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

Preflight checks SDDM boot configuration and records diagnostics before changing
services. It does not inspect the caller's terminal or login sessions.
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
actual start.

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

## Capture the actual TTY login screen

Reinstall with `akari greetd-test install` to include the current capture script,
and install `grim` on the system. On the actual login screen, press `Print` to
save a PNG for every active display. `Shift+Print` waits three seconds, giving
you time to open an account or session menu. The login compositor handles these
keys without waking the dormant UI or dismissing a menu.

Each capture creates a new directory beneath the current run's
`greeter/session-*/screenshots/<timestamp>-*/`. Images survive SDDM restoration
and are readable from the desktop without sudo. For UID 1000 and the default
log root:

```sh
ls /var/tmp/akari-greetd-test-1000/current/greeter/session-*/screenshots/
akari greetd-test logs --run current --file screenshot
```

Each directory contains `output-1.png`, etc., plus `capture.json` mapping images
to displays and recording their current modes, logical dimensions and scales.
Each display uses its own capture scale, avoiding grim's default highest-scale
resampling on mixed-DPI setups. This does not change the startup
`display-profile.json`; captures after hotplug retain their own display metadata.

Use these actual images as your styling reference. Back on Hyprland, compare
with `akari run sway --theme themes/default --display-profile login` fullscreen
on the same monitor; an ordinary preview window can have a different logical
viewport.

Inspect the latest startup attempt or the test used by recovery:

```sh
akari greetd-test logs
akari greetd-test logs --run current --file backend -n 100
akari greetd-test logs --run current --file flutter --follow
```

`logs` defaults to the caller's latest startup attempt and its `start.log`.
`--run current` selects the last armed test, even after restoration. `--file`
accepts `start`, `backend`, `flutter`, `sway`, `lifecycle`, `screenshot`, `restore` and `journal`.
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
python3 test/support/greetd_screenshot_test.py
python3 test/support/display_profile_test.py
python3 test/support/display_layout_test.py
python3 test/support/sway_session_test.py
```
