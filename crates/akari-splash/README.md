# Native startup screen (`akari-splash`)

`akari-splash` renders Akari's native startup and session-handoff screen. It embeds the portrait artwork and the Quicksand variable font (`assets/OFL.txt`), sharing a single CPU renderer and per-resolution layout cache across desktop window previews and Linux DRM/KMS outputs.

## Preview & CLI usage

Preview the splash screen in a desktop window from the repository root:

```sh
akari run splash
akari run splash --light
```

Or build and invoke the crate directly from the `crates/` Cargo workspace:

```sh
cargo build --locked --manifest-path crates/Cargo.toml -p akari-splash
crates/target/debug/akari-splash window --hold
crates/target/debug/akari-splash window --snapshot /tmp/akari-splash.png
```

- **Background**: Pure black (`#000000`) by default to match the login compositor (`--light` previews the light variant; `--dark` is also accepted).
- **Hold duration**: Defaults to a minimum of 3 seconds after first presentation. `--duration` overrides `AKARI_SPLASH_DURATION` (`0` presents one frame and exits immediately). `--hold` is window-only (`akari run splash`) and keeps the window open until closed or `Escape` is pressed.

## DRM/KMS & VT handoff

- **`kms` mode**: Requires a controlling VT and device access via `libseat` (`logind` or `seatd`). It enumerates primary DRM nodes on the seat, preserves active output modes (or selects preferred modes for connected outputs), and centers the composition on each scanout (cloned connectors share one CRTC).
- **Teardown & scanout retention**: Before exiting, `akari-splash` clears hidden console text and scrollback, restores text mode, releases DRM buffers (`CLOSEFB` when supported by the kernel, falling back to `RMFB`), and drops seat control so the next compositor can acquire DRM master cleanly.
- **Sway background handoff**: During greeter startup, `system/splash.sh` saves a still (`$AKARI_LOG_DIR/splash.png`) that `swaybg` displays while Flutter initializes:

  ```conf
  output * bg "$AKARI_LOG_DIR/splash.png" fit #000000
  ```

- **`clear` mode**: Erases VT console text and scrollback after the login compositor exits.

## Build & test

Build dependencies include `pkg-config`, `libseat` development headers, and Wayland/X11 libraries used by `winit`.

```sh
cargo test --locked --manifest-path crates/Cargo.toml -p akari-splash
cargo clippy --locked --manifest-path crates/Cargo.toml -p akari-splash --all-targets -- -D warnings
```

For physical multi-GPU/VT acceptance criteria, see [`docs/proposals/login-handoff.md`](../../docs/proposals/login-handoff.md).
