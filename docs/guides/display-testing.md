---
title: Test displays and scaling
description: Compare desktop previews, nested Sway, fixed screenshots, and standalone login displays.
---

Run these commands from the repository root after
[environment setup](../getting-started/installation.md). The examples use the
default theme; `--theme PATH` selects another compiled theme.

## Choose a session

| What to check | Session |
| --- | --- |
| Theme layout and local interaction on the current desktop | `preview` |
| Shared login state and keyboard focus across actual monitors | Fullscreen `run` |
| Standalone content scale inside a Wayland desktop | `run sway` |
| Repeatable resolution and screenshots | `run sway --sway-backend headless` |
| Hardware output modes, DRM, PAM, and recovery | [Standalone greetd testing](greetd-testing.md) |

Preview uses demo state. `run` and `run sway` use the mock backend by default;
their frontend still communicates through D-Bus. The compositor workflows need
Python 3, Sway, `swaymsg`, and grim. Native input checks also need wtype.

## Check shared state on several monitors

```sh
fvm dart run tool/akari.dart run --theme themes/default
```

The fullscreen greeter opens a view on each monitor. Click a view to make it
active, select an account, and type into its credential field. The other views
should show the same account, session, and credential text. Move focus to another
view and continue typing; a single Enter press should submit one response.

Escape hides the controls on every display and clears the shared credential
text. Wake resumes the existing authentication prompt. Disconnect the focused
monitor while a prompt is active, then reconnect it: the remaining view should
retain the conversation, and the reconnected view should show its current state.
Each view lays out against its own logical dimensions and scale.

For a single resizable window instead, use `preview` or set
`AKARI_WINDOW_MODE=windowed` before `run`. Quit with `q` in the launching terminal.

## Compare a nested session with standalone login

Start with the project reference when no login capture is available:

```sh
fvm dart run tool/akari.dart run sway --theme themes/default \
  --display-profile reference
```

After completing the [standalone capture workflow](greetd-testing.md), return to
the desktop and require that capture explicitly:

```sh
fvm dart run tool/akari.dart run sway --theme themes/default \
  --display-profile login
```

Check the printed source and output targets before comparing. `login` fails if
there is no valid capture; the default `auto` can fall back to the reference.
Use `--dry-run` to inspect profile selection without importing or starting it.
The [CLI reference](../reference/cli.md#sway-sessions-and-display-profiles)
defines capture selection, persistence, and multi-output mapping.

On Hyprland, fullscreen the nested window using your normal desktop shortcut.
Compare it on the same physical monitor and mode as the standalone test. The
session compensates for the host monitor's scale; a tiled window can have a
different viewport. Move it to another monitor or resize it to check that the
viewport and compensated scale update while the theme keeps running.

For actual login-screen images, use `Print` or `Shift+Print` in the
[TTY capture workflow](greetd-testing.md#capture-the-actual-tty-login-screen).

## Capture a fixed resolution

```sh
fvm dart run tool/akari.dart run sway --theme themes/default \
  --display-profile reference --sway-backend headless \
  --resolution 1920x1080 --scale 1.6
```

This profile produces a 1200×675 logical viewport and a 1920×1080 output image.
Headless needs no active desktop. It remains a live session: inspect the printed
screenshot paths and quit with `q` in the launching terminal.

The session captures each output after all greeter windows appear. The initial
images stay under `build/tool/runs/<run-id>/sway/screenshots/`; they are not a
continuous screenshot recording. `display-report.json` and `outputs.json` track
the adopted display settings. With `--report PATH`, the CLI report's `artifacts`
points to these files, and its `display` field includes the display report.

For headless checks, compare the requested `target` with `actual` and require
`matched: true`. On Hyprland, inspect `effective_target`, including `host_monitor`
and `host_scale`, because the outer compositor owns window dimensions. Inner
image dimensions can differ from TTY images while displayed content size agrees.

## Diagnose a comparison

| Symptom | Next step |
| --- | --- |
| `login` reports no valid profile | Reinstall the current harness and complete a standalone test that publishes `display-profile.json`; inspect the saved run's logs |
| An override is rejected for several outputs | Use `--display-profile reference` for a single-output resolution or scale override |
| Nested startup needs a Wayland desktop | Run from an active Wayland session, or select `--sway-backend headless` |
| Headless reports output drift | Read `display-report.json` checks and `sway.log`; a mismatched output fails the session |
| A Hyprland comparison has a different viewport | Compare fullscreen on the same monitor and physical mode; inspect the effective target's host scale |
| Expected controls are absent in the initial image | Check the theme's dormant-state conditions; screenshots capture the initial rendered state |

Run the [native regression checks](testing.md#native-display-regressions) to cover
mixed scales, hotplug, and the nested output matrix. Those checks complement the
standalone hardware test.
