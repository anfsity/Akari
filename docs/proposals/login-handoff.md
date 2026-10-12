# Login handoff experiments

Status: the ASCII transition is implemented for testing on real VTs. The
graphics-mode alternative remains a retained option. Visual continuity across
Sway/greetd handoff has not yet been verified on hardware.

## Current boundary

Akari discovers the selected desktop command from session desktop files and
submits it through greetd's `start_session(cmd, env)` request. The user command
starts after the greeter process exits. Today the Sway greeter and user desktop
use the configured greetd VT, leaving a possible text-console interval between
compositors.

The generic Akari session launcher wraps the discovered command without editing
distribution desktop files or recognizing individual desktops. It is part of
the installed backend, preserves command arguments and session environment,
and execs the desktop with its original process identity. User-session logging
belongs in the user's XDG state directory.

## Option: graphics-mode transition

Explore the SDDM approach of clearing the target VT and setting `KD_GRAPHICS`
during handoff, with desktop output redirected to logs. Determine where this
operation must happen: a user launcher cannot act before its execution begins.
Sway or greetd may change terminal state during that earlier interval.

Verify normal login, startup failure, desktop exit, and VT switching on hardware.
Confirm terminal restoration and whether the earliest text flash is eliminated.
Keep terminal operations conditional on an actual supported console session.

## Implemented experiment: ASCII transition screen

`scripts/ascii-transition.py` contains a FIGlet Slant AKARI wordmark and a cyan
light sweep. Its source is embedded in the backend so both greeter and user
executor use the same implementation from their pinned release.

Production and harness launchers prepare a cleared VT buffer before starting
Sway, and again before asking Sway to exit. Preparation leaves the cursor
visible in case user execution never begins. The user executor starts the
animator before execing the desktop. Desktop output stays redirected to its
private session log, and normal Akari log-path messages no longer reach the VT.

The renderer opens the controlling terminal and uses `KDGETMODE` to exclude
PTYs and missing consoles. It never sets display/keyboard modes or switches
VTs. Rendering follows actual terminal dimensions and falls back to a compact
wordmark on small consoles. It clears once, then updates the wordmark in place.

The animator detaches, allowing the executor to keep desktop process identity,
signals, and exit status. A pidfd follows that session across exec without PID
reuse ambiguity. Animation stops on graphics takeover, session exit, a stop
signal, or a 15-second limit, and restores the cursor. Renderer errors are logged
and do not prevent desktop startup. Animation requires Python's Linux pidfd
support; a failure leaves the prepared static frame and is recorded in the log.

Preview the animation in an ordinary terminal without operating a VT:

```sh
python3 scripts/ascii-transition.py preview
```

When piped, preview prints only the static ASCII wordmark. Preparation and
animation on a real VT are invoked by the installed backend, not this preview.

Verify that terminal contents survive Sway exit and greetd handoff, including
console resets and display-mode changes. Check different console dimensions,
startup failure, desktop exit, and cursor restoration. Do not use continuous
redrawing to compete with logs. An ASCII screen needs text-mode rendering;
graphics mode is a separate transition strategy.

Neither option guarantees that compositor mode changes avoid a short black
screen. Nested and headless tests cannot establish the visual hardware result.

## References

- [greetd session protocol](https://manpages.debian.org/testing/greetd/greetd-ipc.7.en.html)
- [SDDM VT handling](https://github.com/sddm/sddm/blob/v0.21.0/src/common/VirtualTerminal.cpp)
- [SDDM session launch and logging](https://github.com/sddm/sddm/blob/v0.21.0/src/helper/UserSession.cpp)
