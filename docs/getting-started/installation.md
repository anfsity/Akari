---
title: Environment setup
description: Prepare the Linux toolchain for Akari development.
---

Akari builds and runs on Linux. Complete the steps below before running previews or builds.

## Prerequisites

### Core build dependencies

| Component | Required packages / tools | Purpose |
| --- | --- | --- |
| Source & SDK | `git`, `python3`, [FVM](https://fvm.app/) | Manage the pinned Flutter SDK (`3.47.3`) in `.fvmrc` and run workflow scripts |
| Rust & seat | `rustc`, `cargo`, `libseat` headers (`libseat-dev` on Debian/Ubuntu, `seatd` on Arch) | Build the D-Bus backend and native splash |
| Flutter Linux | `clang`, `cmake`, `ninja`, `pkg-config`, GTK 3 & `libepoxy` development files | Compile the Linux Flutter host |
| D-Bus & process tools | `dbus-daemon`, `busctl`, `setpriv`, `setsid` | Launch isolated private D-Bus sessions and unprivileged greeter processes |

### Optional workflow tools

- **Nested or headless compositor tests**: `sway`, `swaymsg`, `swaybg`, `grim`
- **Native input regression tests**: `wtype`
- **Real login testing**: `greetd` (see [Standalone greetd testing](../guides/greetd-testing.md))

## Initialize the repository

1. Clone the repository and bootstrap the pinned SDKs and dependencies:

   ```sh
   git clone https://github.com/anfsity/Akari.git
   cd Akari
   bash scripts/bootstrap-toolchain.sh
   ```

   `bootstrap-toolchain.sh` installs the pinned Flutter version from `.fvmrc`, enables Flutter Linux desktop support, resolves the root Dart Pub Workspace dependencies, generates built-in theme scene code, and fetches locked Cargo workspace dependencies.

2. Verify your environment:

   ```sh
   bash scripts/check-toolchain.sh
   # Or also require Sway/greetd runtime binaries:
   bash scripts/check-toolchain.sh --runtime
   ```

:::note
`bootstrap-toolchain.sh` does not install system packages. Without `--runtime`, `check-toolchain.sh` reports missing `sway`/`greetd` binaries and unset `WAYLAND_DISPLAY` as warnings so headless builds and unit tests still succeed.
:::

## Install the `akari` launcher

Install a user-level `akari` command and shell completion so you do not need to type `fvm dart run packages/akari_cli/bin/akari.dart`:

```sh
# For zsh
fvm dart run packages/akari_cli/bin/akari.dart install cli --shell zsh

# For bash
fvm dart run packages/akari_cli/bin/akari.dart install cli --shell bash
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
