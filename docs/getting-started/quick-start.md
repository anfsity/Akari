---
title: Quick start
description: Preview a theme, run the mock greeter, and build a native bundle.
---

Run these commands from the repository root after [environment setup](installation.md).

## Preview a theme

```sh
fvm dart run tool/akari.dart preview --theme themes/fallback
```

The fallback theme is a small, static example. To preview the default theme:

```sh
fvm dart run tool/akari.dart preview --theme themes/default
```

Preview opens one resizable desktop window, automatically demonstrates face
recognition success and password fallback, and exits after both journeys. It uses
controlled frontend authentication events without a backend, camera, or PAM.
Each journey checks prompts, credential focus, and a simulated session handoff.
Use `--scenario face-success` or `--scenario password-fallback` to select one.
A failed journey produces a nonzero exit status and retains logs in `build/tool/runs/`.

To inspect the native loading animation separately, run
`fvm dart run tool/akari.dart run splash`. It stays open until closed or Escape is
pressed and does not launch a login screen. Real VT handoff still needs hardware.

## Run the mock backend

```sh
fvm dart run tool/akari.dart run --theme themes/fallback
```

This starts the Flutter greeter and Rust mock backend on a private D-Bus session.
It exercises the same frontend transport as production. The mock conversation
accepts `password`; it does not authenticate a system account or launch a real
desktop session. The greeter defaults to fullscreen; use
`AKARI_WINDOW_MODE=windowed` before the command for a windowed session.

Debug `run` sessions reload Dart and assets on save, regenerating changed scene
JSON first. In the launching terminal, `r` regenerates and reloads, `R` restarts,
and `q` quits. Preview runs once and does not hot reload.

Fullscreen renders the same login state on all connected monitors. Follow
[display and scaling testing](../guides/display-testing.md) to check focus,
hotplug, a nested Sway session, or fixed-resolution screenshots.

## Build the production bundle

```sh
fvm dart run tool/akari.dart build --theme themes/fallback --jobs 4
```

Build defaults to release mode and builds both the frontend and production Rust
backend. A successful build publishes `build/out/fallback` for the frontend
bundle and `build/out/backend` for the backend executable. Keep the full Flutter
bundle together when distributing it.

Building does not install or switch a display manager. Use the dedicated
[greetd testing guide](../guides/greetd-testing.md) when testing real login.

Next, [create a theme](../guides/themes.md) or browse the
[implementation map](../architecture/code-map.md).
