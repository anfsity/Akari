# Standalone greetd testing

The maintained test harness lives in `scripts/greetd-test/` and installs into
`/opt/mozais-test`. It uses the production backend: authentication talks to greetd
and power actions call logind, performing actual suspend, reboot and shutdown.
Boot configuration stays on SDDM. Desktop development with `mozais run` still
uses mock authentication and mock power by default.

Build and install while no previous test or timer is active:

```sh
sudo bash scripts/greetd-test/install.sh
```

The installer first builds the current repository's default theme and production
backend in Linux release mode with four build jobs. It runs the build as the sudo
caller (or the repository owner when invoked directly as root), keeping SDK and
repository caches owned by that user. SDK selection uses the same repository
configuration and `MOZAIS_FLUTTER_BIN` / `MOZAIS_DART_BIN` overrides as the CLI.
A failed build aborts installation before any installed files or backups change.

After a successful build, installation backs up the previous frontend, backend,
scripts and configuration beneath `/opt/mozais-test/backups/`. It does not switch
display managers.
The installer expects the existing test setup's `greeter` account and writable
`/opt/mozais-test/state` directory.

Save work, log out of the desktop, log in on tty3, then run:

```sh
sudo /opt/mozais-test/start.sh
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
sudo /opt/mozais-test/restore.sh
```

Logs live outside `/opt`, under `/var/tmp/mozais-greetd-test-<caller-uid>/`.
For a user with UID 1000 this is `/var/tmp/mozais-greetd-test-1000/`.
All users can read startup, frontend, backend, compositor and recovery logs
directly, including while the test is running, without sudo or special group
membership. Direct root invocation uses UID 0 and keeps the same read access.
Log directories use mode `0755`; log files use mode `0644`. Only their owners
and root can write to them.

Each startup attempt that reaches log setup gets its own
`<timestamp>-<pid>/start.log`. Startup prints its log directory before preflight.
The `latest` symlink points to the latest attempt, including preflight failures.
The `current` symlink points to the latest armed test. The installation keeps
only a `current-run` pointer to that directory for launching and recovery, so a
later rejected attempt cannot redirect recovery logs. Restore prints the test's
log directory too.

Each greeter launch retains `backend.log`, `flutter.log`, `sway.log`,
`lifecycle.log` and `outputs.json` under its own `greeter/session-*/` directory;
returning from the desktop does not overwrite earlier logs. Recovery saves the
test and SDDM journal plus its own timestamp/result.

Inspect the latest startup attempt or the test used by recovery:

```sh
readlink -f /var/tmp/mozais-greetd-test-$(id -u)/latest
cat /var/tmp/mozais-greetd-test-$(id -u)/latest/start.log
tail -n 100 /var/tmp/mozais-greetd-test-$(id -u)/current/greeter/session-*/backend.log
```

Set an absolute custom location when starting a test:

```sh
sudo MOZAIS_TEST_LOG_DIR=/var/tmp/my-mozais-test /opt/mozais-test/start.sh
```

The greeter must be able to traverse the parent directories of a custom location;
startup checks access before stopping SDDM. A private home directory usually
prevents this, so use a location beneath `/var/tmp`. Recovery resolves the saved
pointer automatically and does not require the custom setting again.

For live system service output, use `sudo journalctl -u mozais-test.service -f`;
the directly readable `journal.log` is saved during recovery. Reinstall the
scripts to make these changes available in `/opt/mozais-test`. Existing logs in
the old `/opt/mozais-test/test-runs/` directory remain there.

The standalone login environment is the visual reference. Its output scale
remains 1 by default and Sway records the actual output mode and scale in
`outputs.json`. Personal Hyprland development settings should make the Mozais
preview match this login environment. Do not change the login output scale to
follow a developer's desktop settings. Desktop scaling compatibility belongs to
that developer's local preview setup, outside the production renderer.

Validate harness control flow without root or live system changes:

```sh
python3 test/support/greetd_test_workflow_test.py
```
