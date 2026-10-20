---
title: Quick start
description: Preview a theme, run the mock greeter, and build a native bundle.
---

Run these commands from the repository root after completing [environment setup](installation.md).

## 1. Preview a theme

Run an automated UI walkthrough in a single resizable desktop window:

```sh
# Minimal static fallback theme
fvm dart run tool/akari.dart preview --theme themes/fallback

# Default theme
fvm dart run tool/akari.dart preview --theme themes/default
```

`preview` drives frontend authentication events without starting a backend, camera, or PAM session. By default, it runs both `face-success` and `password-fallback` journeys and exits automatically.

- Run a single scenario with `--scenario face-success` or `--scenario password-fallback`.
- If a check fails, `preview` exits with a nonzero code and saves logs under `build/tool/runs/`.

:::tip[Preview the native splash]
To inspect the standalone loading screen without launching the greeter, run:
```sh
fvm dart run tool/akari.dart run splash
```
Press `Escape` or close the window to exit.
:::

## 2. Run with the mock backend

Start the Flutter greeter and Rust mock backend over an isolated private D-Bus session:

```sh
# Fullscreen across connected monitors (default)
fvm dart run tool/akari.dart run --theme themes/fallback

# Windowed mode for desktop iteration
AKARI_WINDOW_MODE=windowed fvm dart run tool/akari.dart run --theme themes/fallback
```

The mock backend exercises the production D-Bus transport without touching system accounts:

- Enter `password` to simulate a successful login.
- Saving Dart files or `*.scene.json` automatically regenerates scene code and hot reloads the window.

| Terminal key | Action |
| --- | --- |
| `r` | Regenerate scenes and hot reload |
| `R` | Hot restart |
| `q` | Quit the session |

For multi-monitor focus, hotplug, nested Sway scaling, or fixed-resolution screenshots, see [Test displays and scaling](../guides/display-testing.md).

## 3. Build a release bundle

Compile the selected theme and the production Rust backend in release mode:

```sh
fvm dart run tool/akari.dart build --theme themes/fallback --jobs 4
```

Successful builds link outputs under `build/out/`:

- `build/out/fallback`: complete Flutter Linux bundle (distribute the entire directory together).
- `build/out/backend`: production Rust backend executable.

:::note
`build` only compiles artifacts; it does not modify system services. To test real PAM login in a TTY, follow [Standalone greetd testing](../guides/greetd-testing.md).
:::

## Next steps

- [Develop a theme](../guides/themes.md)
- [Browse the code map](../architecture/code-map.md)
