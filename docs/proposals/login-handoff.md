# Native login handoff

> [!NOTE]
> **Status**: Native window preview and process-ordering tests pass. The DRM/KMS implementation is wired into both VT launch boundaries; visual continuity, VT switching, and GPU-specific behavior still require hardware acceptance.

## 1. Launch boundaries

| Transition stage | Owner | Handoff behavior |
| --- | --- | --- |
| **Before Greeter Sway** | `scripts/splash.sh` + `akari-splash kms` | Starts the private D-Bus and waits for the backend, then runs `akari-splash kms` and waits for it to exit before starting Sway. Saves a snapshot (`splash.png`) displayed by `swaybg` while Flutter loads. |
| **Before User Desktop** | User-side session launcher (`session_launch.rs`) | After greeter exit, initializes `startup-*.log` and `session-*.log`, runs `akari-splash kms`, and `exec`s the desktop command directly so the desktop retains the launcher's PID and exit status. |

- Signals (`SIGINT`, `SIGTERM`) and launcher exit cleanly terminate and reap child processes.
- Authentication stays inside the backend actor and never acquires DRM master.

## 2. Rendering & KMS lifetime

`akari-splash` is a standalone Rust binary embedding the portrait PNG and Quicksand font:

- **Shared CPU renderer**: Used by both the desktop window preview (`akari run splash`) and KMS outputs. Scaled portraits and glyph layers are cached per output resolution.
- **Timing & background**: Pure black background (`#000000`) with a default minimum hold of `3` seconds from first presentation (`AKARI_SPLASH_DURATION=0` disables the hold; `akari run splash` stays open until closed).
- **Multi-GPU & multi-output KMS**: Acquires the seat via `libseat` (logind/seatd), enumerates all primary DRM nodes and active CRTCs without hardcoding a GPU index, and maps XRGB dumb buffers at each display's native resolution (cloned connectors share one buffer).
- **Teardown & scanout retention**: Drawing stops before releasing resources and seat control. Uses `CLOSEFB` (falling back to `RMFB` on older kernels) so the kernel retains the last frame until the next compositor sets a mode.

## 3. Console & log guarantees

- **Non-fatal fallback**: Splash errors are logged to `lifecycle.log` / `session-*.log` and never block login. PTYs never enter the KMS path.
- **VT text cleanup**: Both the KMS renderer (before releasing the seat) and the VT launcher (`akari-splash clear` after Sway exits) erase hidden terminal text and scrollback so console output does not flash between compositors.

## 4. Hardware acceptance checklist

Verify both transitions (before Greeter Sway and before the user desktop) on physical VTs:

- [ ] Different GPU vendors, mixed monitor resolutions, and cloned/extended layouts.
- [ ] VT switching during splash hold and compositor startup.
- [ ] Renderer termination, missing DRM devices, compositor startup failure, and desktop logout.
- [ ] No lingering `akari-splash` process, DRM master conflict, stale frame, or visible console text on logout.

## References

- [DRM primary nodes and framebuffer lifetime](https://docs.kernel.org/gpu/drm-uapi.html)
- [libseat API](https://git.sr.ht/~kennylevinsen/seatd/tree/master/item/include/libseat.h)
- [greetd session protocol](https://manpages.debian.org/testing/greetd/greetd-ipc.7.en.html)
