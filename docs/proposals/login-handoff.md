# Login handoff experiments

Status: retained options, pending real VT testing. Neither option is selected
or implemented. These notes do not change the login configuration.

## Current boundary

Akari discovers the selected desktop command from session desktop files and
submits it through greetd's `start_session(cmd, env)` request. The user command
starts after the greeter process exits. Today the Sway greeter and user desktop
use the configured greetd VT, leaving a possible text-console interval between
compositors.

A generic Akari session launcher could wrap the discovered command without
editing distribution desktop files or recognizing individual desktops. It
should be installed with each release, preserve command arguments and session
environment, and define signal, exit-status, and terminal restoration ownership.
User-session logging belongs in the user's XDG state directory.

## Option: graphics-mode transition

Explore the SDDM approach of clearing the target VT and setting `KD_GRAPHICS`
during handoff, with desktop output redirected to logs. Determine where this
operation must happen: a user launcher cannot act before its execution begins.
Sway or greetd may change terminal state during that earlier interval.

Verify normal login, startup failure, desktop exit, and VT switching on hardware.
Confirm terminal restoration and whether the earliest text flash is eliminated.
Keep terminal operations conditional on an actual supported console session.

## Option: ASCII transition screen

Explore preparing a cleared console with hidden cursor and a simple ASCII
screen before Sway exits, then refreshing it from the user launcher if needed.
Use the actual VT dimensions and redirect desktop output to logs so it cannot
scroll or overwrite the screen. Treat other console writers separately.

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
