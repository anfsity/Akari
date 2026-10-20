---
title: Test displays and scaling
description: Compare desktop previews, nested Sway, fixed screenshots, and standalone login displays.
---

Run these commands from the repository root after [environment setup](../getting-started/installation.md). Replace `themes/default` with `--theme PATH` to test another theme.

## Choose a workflow

| Goal | Command / Workflow |
| --- | --- |
| Automated login UI walkthrough on the desktop | `akari preview` |
| Shared login state and focus across physical monitors | `akari run` (fullscreen default) |
| Reproduce standalone TTY scaling inside a Wayland desktop | `akari run sway` |
| Capture repeatable fixed-resolution screenshots without a desktop | `akari run sway --sway-backend headless` |
| Verify hardware modes, DRM/KMS splash, PAM, and SDDM recovery | [Standalone greetd testing](greetd-testing.md) |

:::note
`run` and `run sway` use the Rust mock backend over a private D-Bus session by default. Sway workflows require `python3`, `sway`, `swaymsg`, and `grim`.
:::

## Check shared state across multiple monitors

```sh
fvm dart run tool/akari.dart run --theme themes/default
```

In fullscreen mode, Akari opens one view per connected monitor using each output's logical size and scale. Verify the following behaviors:

1. **Shared state**: Select an account and type a password on one monitor—all other monitors update simultaneously.
2. **Active focus**: Move focus to another monitor and press `Enter`—only one authentication response is submitted.
3. **Dormant state (`Escape`)**: Pressing `Escape` hides controls on all displays and clears typed text without cancelling the active PAM prompt; waking the UI resumes the same prompt.
4. **Monitor hotplug**: Disconnect and reconnect the focused monitor during an active prompt—remaining displays keep the conversation alive, and reconnected displays adopt the current state.

:::tip
Set `AKARI_WINDOW_MODE=windowed` before `run` if you only need a single resizable window. Press `q` in the terminal to quit.
:::

## Compare a nested session with standalone login

1. **Without a saved TTY capture**, start with the built-in `1920x1080` (scale `1.0`) reference profile:

   ```sh
   fvm dart run tool/akari.dart run sway --theme themes/default \
     --display-profile reference
   ```

2. **After running a [standalone greetd test](greetd-testing.md)**, replay the captured hardware display profile on your desktop:

   ```sh
   fvm dart run tool/akari.dart run sway --theme themes/default \
     --display-profile login
   ```

   - `--display-profile login` fails if no valid TTY capture exists, whereas the default `auto` falls back to `reference`.
   - Pass `--dry-run` to inspect which profile would be selected without launching Sway.

3. **Comparing on Hyprland**: Fullscreen the nested Sway window on the same physical monitor used during the TTY test. `run sway` automatically compensates for your outer Hyprland monitor scale (`inner_scale = login_scale / hyprland_scale`) so the fullscreen logical viewport matches TTY login.

## Capture fixed-resolution screenshots

Use `--sway-backend headless` to render an exact resolution and scale without requiring an active Wayland desktop:

```sh
fvm dart run tool/akari.dart run sway --theme themes/default \
  --display-profile reference --sway-backend headless \
  --resolution 1920x1080 --scale 1.6
```

- At `1920x1080` and scale `1.6`, the logical viewport is `1200x675` and the output PNG is `1920x1080`.
- Once all greeter views appear, initial screenshots are saved under `build/tool/runs/<run-id>/sway/screenshots/`, alongside `display-report.json` and `outputs.json`.
- Press `q` in the terminal when finished.

## Troubleshooting

| Symptom | Resolution |
| --- | --- |
| `--display-profile login` reports no valid profile | Reinstall the harness (`akari greetd-test install`) and run a standalone test so `display-profile.json` is published. |
| `--resolution` or `--scale` is rejected on a multi-output profile | Add `--display-profile reference` to apply single-output overrides. |
| Nested Sway fails to start without a Wayland session | Run inside an active Wayland desktop, or pass `--sway-backend headless`. |
| Headless session fails with output drift | Check `display-report.json` and `sway.log`—headless mode requires exact match between requested `target` and `actual`. |
| Hyprland window viewport differs from TTY | Make the nested window fullscreen on the same physical monitor and check `effective_target.host_scale` in `display-report.json`. |
| Login controls are missing in the initial screenshot | Initial screenshots capture the startup state; check whether your theme starts in the dormant state (`isDormant`). |

For automated multi-monitor and nested scale checks, see [Native display regressions](testing.md#native-display-regressions).
