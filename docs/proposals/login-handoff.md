# Native login handoff

Status: the native window preview and process-ordering tests pass. The DRM/KMS
implementation is connected to both VT launch boundaries; visual continuity,
VT switching and driver-specific behavior still require hardware acceptance.
The previous ASCII animator has been removed.

## Launch boundaries

The production and greetd-test launchers start the private bus and wait for the
backend before running the pinned release's `akari-splash kms`. `scripts/splash.sh`
owns the renderer and compositor, waiting for the renderer to exit before
starting Sway, so D-Bus startup does not extend the blank interval after the
animation. Signals terminate and reap both children; launcher death also stops
the renderer. The launcher retains its controlling VT for cleanup after Sway.

The KMS renderer saves a still in the greeter's log directory. The supplied Sway
configuration displays it through `swaybg` until the Flutter login screen is
visible, with a black fallback if no image was saved. Existing production configs
are preserved; their background line needs the change documented in
[`splash/README.md`](../../splash/README.md). The image covers Flutter startup,
not the earlier VT/logind reset or user-desktop initialization.

After successful authentication, greetd starts the user launcher only after the
greeter has exited. The launcher captures native shell output in `startup-*.log`,
initializes the session log, and runs the same splash executable before execing
the desktop. The desktop retains the launcher's process identity and exit status.
Authentication remains in the existing backend actor and does not acquire DRM.

## Rendering and lifetime

The independent Rust program embeds the selected portrait PNG and Quicksand
font. Both its desktop window and KMS outputs use one CPU renderer. Images and
fonts load once; scaled portraits and glyph layers are cached per output size.
Only the slight float and status dots change each frame.

The background defaults to pure black (`#000000`), matching the login compositor.
The minimum display time defaults to 3 seconds, starting at the first successful
presentation. Zero removes the artificial hold. `akari run splash` keeps the
independent window preview open until closed. `AKARI_SPLASH_DURATION` can be set
in the VT launcher's environment and is forwarded through greetd to the user
launcher. This time is not a desktop startup timeout or a desktop readiness signal.

KMS access goes through libseat's logind/seatd management. The program enumerates
primary DRM nodes, connected outputs, active CRTCs and their modes. Each output
uses its actual resolution; cloned connectors share a buffer. It creates and maps
XRGB dumb buffers without selecting a fixed GPU number.

On normal exit, failure, termination or seat revocation, drawing stops before
resources and seat control are released. Revocation ends the renderer permanently;
a later enable cannot revive it. No previous compositor state is restored after
release. CLOSEFB retains the last scanout when the kernel and console transition
permit; older kernels fall back to RMFB. Console mode restoration or a compositor
mode change may still blank the screen. Process exit is the release acknowledgement.

## Console and log guarantees

Renderer errors go to the existing lifecycle/session logs and allow normal login
to continue. PTYs cannot enter the KMS path. After Sway exits, the VT-owning
launcher runs `akari-splash clear` to erase hidden terminal text and scrollback
without acquiring display control.
The KMS renderer clears these again during its own cleanup, before releasing the
seat. Launcher, native shell and desktop output retain their existing redirection.
No detached animation can repaint the console after the desktop takes over.

## Hardware acceptance

Check both transitions on a real VT: before Sway and before the user desktop.
Cover different GPUs, mixed resolutions, cloned and extended outputs, VT switches,
renderer termination, missing devices, compositor startup failure and logout.
Confirm no lingering process, DRM master conflict, old frame or startup log returns
on desktop exit. Measure the actual blank interval between compositors; nested
and headless tests cannot establish this result.

## References

- [DRM primary nodes and framebuffer lifetime](https://docs.kernel.org/gpu/drm-uapi.html)
- [libseat API](https://git.sr.ht/~kennylevinsen/seatd/tree/master/item/include/libseat.h)
- [greetd session protocol](https://manpages.debian.org/testing/greetd/greetd-ipc.7.en.html)
