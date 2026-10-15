# Native startup screen

`akari-splash` embeds the selected portrait PNG and Quicksand variable font.
The CPU renderer and cached layout are shared by the desktop window and Linux
DRM/KMS outputs. No browser, Flutter engine or authentication service runs here.

```sh
cargo build --locked --manifest-path splash/Cargo.toml
splash/target/debug/akari-splash window
splash/target/debug/akari-splash window --snapshot /tmp/akari-splash.png
```

The default background is pure black (`#000000`), matching the login compositor.
Use `--light` to preview the light variant; `--dark` remains accepted.
The default minimum display time is 3 seconds after the first successful
presentation. `--duration` overrides `AKARI_SPLASH_DURATION`; zero skips the
artificial hold while still presenting one frame. Closing the window or pressing
Escape ends the preview early. SIGINT, SIGTERM, SIGHUP and launcher death stop it.

`kms` requires a real controlling VT and device access through libseat (logind or
seatd). It enumerates primary DRM nodes on the seat, preserves active output
modes, selects preferred modes for other connected outputs and centers the same
composition separately on each scanout. Cloned connectors share their CRTC.
It neither selects a fixed card number nor restores a previous compositor's state.
VT revocation ends this process permanently, before acknowledging the disable.

The launcher waits for process exit before starting the next compositor. Cleanup
clears the hidden console text and scrollback, restores text mode, closes DRM
buffers/devices and releases seat control. CLOSEFB retains scanout when the
kernel and console transition permit; older kernels fall back to RMFB. A driver
or compositor mode change can still blank the screen. `clear` only erases VT
text; it is also used before the login compositor exits.

For login startup, the private bus and backend reach readiness before the splash
runs. The launcher saves a still of the splash in the greeter's log directory;
Sway uses it as its background until Flutter covers it with the login screen.
This requires `swaybg`. If the renderer cannot save a still, Sway uses the black
fallback color. Existing production installations preserve `sway.conf`; update
its background line to enable this hold:

```conf
output * bg "$AKARI_LOG_DIR/splash.png" fit #000000
```

This covers Flutter startup after Sway acquires the display. It does not cover
the VT/logind reset between KMS clients, or Hyprland's initialization and desktop
wallpaper startup. Those transitions still need hardware measurement and
compositor-side coordination to guarantee continuous animation.

Build dependencies include `pkg-config`, libseat development files and the
Wayland/X11 dependencies used by winit. The installed executable needs libseat.
Quicksand's license is in `assets/OFL.txt`; the portrait is the selected generated
artwork from the earlier local visual study, copied without modification.

```sh
cargo test --locked --manifest-path splash/Cargo.toml
cargo clippy --locked --manifest-path splash/Cargo.toml --all-targets -- -D warnings
```

Window testing does not validate real VT handoff. Hardware acceptance must cover
both transitions, multiple GPUs/displays, VT switching, compositor failure,
logout, termination and the visible blank interval between compositors.
