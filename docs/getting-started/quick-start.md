---
title: Quick start
description: Preview a theme, run the mock greeter, and build a native bundle.
---

Run these commands from the repository root after [environment setup](installation.md).

## Preview a theme

```sh
fvm dart run tool/mozais.dart preview --theme themes/fallback
```

The fallback theme is a small, static example. To preview the default theme:

```sh
fvm dart run tool/mozais.dart preview --theme themes/default
```

Preview uses simulated frontend state and does not require a backend. It opens
a resizable desktop window. The CLI resolves the theme's dependencies, generates
its scene Dart, and creates a reusable application host.

In debug mode, saving Dart or asset changes triggers hot reload. Scene JSON
changes are regenerated before reload. In the launching terminal, `r` regenerates
and reloads, `R` restarts, and `q` quits.

## Run the mock backend

```sh
fvm dart run tool/mozais.dart run --theme themes/fallback
```

This starts the Flutter greeter and Rust mock backend on a private D-Bus session.
It exercises the same frontend transport as production. The mock conversation
accepts `password`; it does not authenticate a system account or launch a real
desktop session. The greeter defaults to fullscreen; use
`MOZAIS_WINDOW_MODE=windowed` before the command for a windowed session.

Fullscreen renders the same login state on all connected monitors. Follow
[display and scaling testing](../guides/display-testing.md) to check focus,
hotplug, a nested Sway session, or fixed-resolution screenshots.

## Build the production bundle

```sh
fvm dart run tool/mozais.dart build --theme themes/fallback --jobs 4
```

Build defaults to release mode and builds both the frontend and production Rust
backend. A successful build publishes `build/out/fallback` for the frontend
bundle and `build/out/backend` for the backend executable. Keep the full Flutter
bundle together when distributing it.

Building does not install or switch a display manager. Use the dedicated
[greetd testing guide](../guides/greetd-testing.md) when testing real login.

Next, [create a theme](../guides/themes.md) or browse the
[implementation map](../architecture/code-map.md).
