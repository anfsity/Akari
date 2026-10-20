---
title: Environment setup
description: Prepare the Linux toolchain for Akari development.
---

Akari builds and runs on Linux. Complete the steps below before running previews or builds.

## Prerequisites

### Core build dependencies

| Component | Required packages / tools | Purpose |
| --- | --- | --- |
| Source & SDK | `git`, [FVM](https://fvm.app/) | Manage the pinned Flutter SDK in `.fvmrc` |
| Rust & seat | `rustc`, `cargo`, `libseat` headers (`libseat-dev` on Debian/Ubuntu, `seatd` on Arch) | Build the D-Bus backend and native splash |
| Flutter Linux | `clang`, `cmake`, `ninja`, `pkg-config`, GTK 3 development files | Compile the Linux Flutter host |
| D-Bus | `dbus-run-session`, `busctl` | Run isolated backend sessions |

### Optional workflow tools

- **Nested or headless compositor tests**: `sway`, `swaymsg`, `swaybg`, `python3`, `grim`
- **Native input regression tests**: `wtype`
- **Real login testing**: `greetd` (see [Standalone greetd testing](../guides/greetd-testing.md))

## Initialize the repository

1. Clone the repository and bootstrap the pinned SDKs and dependencies:

   ```sh
   git clone https://github.com/anfsity/Akari.git
   cd Akari
   bash scripts/bootstrap-toolchain.sh
   ```

   `bootstrap-toolchain.sh` installs the Flutter version from `.fvmrc`, enables Flutter Linux desktop support, resolves root Dart packages, and fetches locked Cargo dependencies.

2. Verify your environment:

   ```sh
   bash scripts/check-toolchain.sh
   ```

:::note
`bootstrap-toolchain.sh` does not install system packages. When running `check-toolchain.sh` outside a live Wayland session, a missing `WAYLAND_DISPLAY` warning only affects nested compositor windows—headless tests still work.
:::

## Install the `akari` launcher

Install a user-level `akari` command and shell completion so you do not need to type `fvm dart run tool/akari.dart`:

```sh
# For zsh
fvm dart run tool/akari.dart install cli --shell zsh

# For bash
fvm dart run tool/akari.dart install cli --shell bash
```

Open a new terminal (or source the environment file printed by the installer) to activate `akari`.

:::caution
The installed `akari` launcher points to your current repository path. Re-run `install cli` if you move the checkout.
:::

## Deploy for boot login

On a machine with `systemd`, `greetd`, and `sway` installed, you can build and register Akari as your system display manager:

```sh
akari install
akari login enable
```

Neither command interrupts your current desktop session. For PAM keyring setup, logs, and rollback, see [Production login installation](../reference/cli.md#production-login-installation).

Next, continue to the [Quick start](quick-start.md).
