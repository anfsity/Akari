---
title: Standalone greetd testing
description: Build and install the real-login harness, capture displays, inspect logs, and restore SDDM.
---

The standalone test harness in `scripts/greetd-test/` installs into `/opt/akari-test`. It runs the production backend against real `greetd` and `systemd-logind` while keeping your boot display manager on SDDM and arming automatic recovery timers.

:::caution
Because the harness uses the production backend, power actions (`Suspend`, `Reboot`, `PowerOff`) execute on the real host. Use `akari run` for mock authentication and mock power during ordinary desktop development.
:::

## User session environment

### Shell & profile initialization

Production and test greetd configurations enable `source_profile`:

1. `greetd` loads `/etc/profile` and `~/.profile`.
2. Akari forwards the authenticated user's session command to `$SHELL` in non-interactive login mode (`bash`, `sh`, `zsh`, and `fish` are supported).
3. Your login shell loads its native login files (such as `.zprofile` or fish config outside `status is-interactive`; interactive `.zshrc` is not read).
4. The user-side executor preserves `argv`, sets `LANG=C.UTF-8` only when `LANG` is unset/empty, and launches the desktop.

:::note[Upgrading older installations]
Installations preserve existing `/etc/akari/greetd.toml` files. When upgrading an older setup, remove `source_profile = false` (or set `source_profile = true`). Reinstalling the test harness updates its config and backend together.
:::

### Session & startup logs

| Log file | Location | Contents |
| --- | --- | --- |
| `startup-*.log` | `${XDG_STATE_HOME:-$HOME/.local/state}/akari/sessions/` | Native login shell stdout/stderr before desktop launch |
| `session-*.log` | `${XDG_STATE_HOME:-$HOME/.local/state}/akari/sessions/` | Desktop process stdout/stderr and launch metadata |
| `lifecycle.log` | Greeter session log directory | Greeter startup and shutdown diagnostics |

### Native DRM/KMS splash

On real VTs, `akari-splash` renders a pure black (`#000000`) loading screen via `libseat` and DRM/KMS before Sway starts and again before the user desktop starts:

- **Minimum hold**: Defaults to 3 seconds from first presentation. Set `AKARI_SPLASH_DURATION` in the greeter launcher environment to adjust both transitions (`0` disables the hold).
- **Sway background handoff**: The supplied Sway config displays a saved snapshot (`output * bg "$AKARI_LOG_DIR/splash.png" fit #000000`) via `swaybg` while Flutter initializes.
- **Console cleanup**: Terminal text and scrollback are cleared before releasing the VT. See the [login handoff proposal](https://github.com/anfsity/Akari/blob/main/docs/proposals/login-handoff.md) for hardware acceptance checks.

## Facial authentication

When the greeter wakes with an account and session selected, Akari automatically starts PAM authentication:

- **Face match**: PAM messages display during recognition, and the desktop launches immediately without password submission.
- **Password fallback**: If recognition times out or no camera is available, the password field regains keyboard focus within the same attempt.

Akari uses [Gaze](https://github.com/GunduLabs/gaze) as its reference face provider. Camera access, face models, timeouts, and fallback rules belong entirely to Gaze and PAM—Akari never captures camera frames.

### Install and verify Gaze

1. On Arch Linux, install `gaze-bin` (not the unrelated `gaze` file watcher) and opt out of automatic `sudo` PAM modification if you only want to test `greetd`:

   ```sh
   sudo install -d -m 0755 /etc/gaze
   sudo touch /etc/gaze/pam-sudo.optout
   yay -S --needed gaze-bin
   sudo systemctl enable --now gazed
   gaze config
   ```

   :::tip[Recommended initial Gaze config]
   Start with CPU inference, `security.level = "medium"`, liveness enabled, and your RGB camera (`usb:VVVV:PPPP` identifier preferred over `/dev/video*`). See Gaze's [installation](https://gaze.gundulabs.com/guide/installation.html) and [configuration](https://gaze.gundulabs.com/guide/configuration.html) guides.
   :::

2. Enroll your face and test recognition from your desktop login account before touching PAM:

   ```sh
   gaze add-face default
   gaze auth --verbose
   gaze doctor
   ```

### Connect greetd on Arch

Once `gaze auth` succeeds, wire Gaze into the stock Arch `greetd` PAM stack:

```sh
akari login enable-gaze --dry-run
akari login enable-gaze
```

What `enable-gaze` does:
- Backs up `/etc/pam.d/greetd` to `/var/lib/akari/greetd.pam.before-gaze`.
- Writes `/etc/pam.d/akari-gaze` and replaces `auth include system-local-login` with `auth substack akari-gaze`.
- Uses a PAM substack so a `sufficient` face match does not skip parent keyring hooks, while falling back to the standard password stack when face recognition fails or is unavailable.

:::note[Keyring unlocking with face login]
Without TPM-backed password storage, a face login does not supply a password token to unlock GNOME Keyring or KWallet automatically. If you enable Gaze's optional keyring integration, also run `akari login configure-keyring --keyring gnome` so the GNOME hook includes `use_authtok`.
:::

To remove the Gaze PAM routing and restore password-only login:

```sh
akari login disable-gaze
```

### Verify real login

When testing with the harness below, verify:
1. Face match logs in without typing a password.
2. Failed scan or covered camera falls back to password login.
3. Switching accounts mid-scan cancels the prior attempt.
4. A locked-out account remains denied even on a face match.

## Install and run the harness

### 1. Build and install

Ensure no previous test or recovery timer is active, then build and install the harness:

```sh
# Install with the default theme
akari greetd-test install

# Or select another theme project
akari greetd-test install --theme themes/preset1
```

`install` compiles the theme and production backend in release mode (`--jobs 4`), backs up previous `/opt/akari-test/` artifacts, and saves your active Sway or Hyprland monitor order to `/opt/akari-test/display-layout.json`.

### 2. Start from a TTY

1. Save your work and log out of your desktop session.
2. Switch to `tty3`, log in, and start the test:

   ```sh
   akari greetd-test start
   ```

   Optional flags:
   - `--scale NUMBER`: Override the login output scale (default `1`).
   - `--log-dir /var/tmp/my-akari-test`: Custom world-traversable log root.
   - `--dry-run`: Print the execution plan without stopping SDDM.

`start` arms recovery before stopping SDDM. SDDM is restored automatically when:
- Setup fails during preflight,
- `akari-test.service` exits (`ExecStopPost`), or
- The 10-minute fallback recovery timer fires.

### 3. Restore SDDM manually

To end a test and return to SDDM from `tty3`:

```sh
akari greetd-test restore

# Emergency fallback if the repository or SDK is unavailable:
sudo /opt/akari-test/restore.sh
```

### 4. Check status and logs

Inspect service state, timers, and log paths without `sudo`:

```sh
akari greetd-test status
akari greetd-test status --format json
```

Logs are world-readable under `/var/tmp/akari-greetd-test-<caller-uid>/` (e.g., `/var/tmp/akari-greetd-test-1000/`):

- `latest`: Symlink to the newest startup attempt (including preflight failures).
- `current`: Symlink to the latest armed test run.
- `current/greeter/session-*/`: Contains `backend.log`, `flutter.log`, `sway.log`, `lifecycle.log`, `outputs.json`, and `display-profile.json`.

Query logs directly through the CLI:

```sh
# Latest start.log
akari greetd-test logs

# Last 100 lines of backend.log from the armed test
akari greetd-test logs --run current --file backend -n 100

# Follow flutter.log in real time
akari greetd-test logs --run current --file flutter --follow
```

Accepted `--file` values: `start`, `backend`, `flutter`, `sway`, `lifecycle`, `screenshot`, `restore`, and `journal`.

## Capture the actual TTY login screen

With `grim` installed on the host, you can capture per-monitor screenshots directly from the live login screen without waking the dormant UI or closing open menus:

| Shortcut | Behavior |
| --- | --- |
| `Print` | Immediately saves a PNG for each active output |
| `Shift+Print` | Waits 3 seconds before capturing (useful for opening account/session menus) |

Screenshots and `capture.json` metadata are saved under `greeter/session-*/screenshots/<timestamp>-*/` and remain readable after SDDM restoration:

```sh
akari greetd-test logs --run current --file screenshot
```

Back on your desktop, `akari run sway` automatically imports `display-profile.json` from the latest valid test so you can [compare nested Sway with standalone login](display-testing.md#compare-a-nested-session-with-standalone-login).

## Offline harness tests

Validate harness scripts without root privileges or stopping your display manager:

```sh
python3 test/support/greetd_test_workflow_test.py
python3 test/support/greetd_screenshot_test.py
python3 test/support/display_profile_test.py
python3 test/support/display_layout_test.py
python3 test/support/sway_session_test.py
```
