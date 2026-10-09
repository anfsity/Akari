---
title: Environment setup
description: Prepare the Linux toolchain for Akari development.
---

## Prerequisites

Akari currently builds and runs on Linux. Install:

- Git and [FVM](https://fvm.app/) to use the repository's Flutter SDK.
- Rust and Cargo for the backend.
- Clang, CMake, Ninja, pkg-config, and GTK 3 development files for Flutter Linux.
- D-Bus tools, including `dbus-run-session` and `busctl`, for backend sessions.

The optional compositor workflows also need Sway, `swaymsg`, Python 3, and grim.
Native input regression checks use wtype. Standalone login testing needs greetd
and the existing test environment described in its guide.

## Check out the project

```sh
git clone https://github.com/anfsity/Akari.git
cd Akari
bash scripts/bootstrap-toolchain.sh
```

Bootstrap installs/selects the SDK specified in `.fvmrc`, enables Flutter Linux
development, resolves root Dart dependencies, and fetches locked Cargo
dependencies. It does not install the Linux system packages listed above.

```sh
bash scripts/check-toolchain.sh
```

The checker covers both ordinary development and the optional Sway/greetd
workflows. A missing `WAYLAND_DISPLAY` is a warning for nested compositor use;
headless compositor tests do not require a live Wayland desktop.

## Optional shell launcher

```sh
fvm dart run tool/akari.dart install cli --shell zsh
```

For bash, use `--shell bash`. Open a new shell or source the environment file
printed by the installer. The installed `akari` command refers to this checkout;
reinstall it after moving the repository.

Proceed to the [quick start](quick-start.md). For alternate SDK locations, see
the [CLI reference](../reference/cli.md).
