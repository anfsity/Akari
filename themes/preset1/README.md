# Preset 1 — Life / Death

A fully procedural interpretation of the supplied diagonal life/death wallpaper.
The background, cherry branches, blossoms, light streaks, rain, drifting petals
and angular weekday lettering are hand-authored Canvas drawing. No generated
image or video is used. Space Grotesk body text includes its OFL license.

Dormant mode keeps the mirrored clock composition. Waking reveals a second
composition: identity in the pale field, desktop choice on the dark right side,
borderless credential text below the branch, and a separate continuation arrow.
There is no login panel. Native text editing and the shared greeter components
retain prompt handling, password masking, authentication recovery and power
actions. Escape closes a menu first; otherwise it returns to dormant mode and
clears credentials. Tab follows account → desktop → credential → continue → power.

Sway is the visual reference for both dormant and login modes. Components scale
from their authored scene bounds, keeping text and icons proportional to the
composition rather than fixed at small logical sizes on larger Sway viewports.
Choice menus anchor to the visible controls, and their native popup text uses
the Material 3 label style.

From the repository root:

```sh
akari run sway --theme themes/preset1 --display-profile reference --mode profile
```

On a Hyprland monitor at scale 1.6 this selects standalone scale 1 and produces
**inner Sway scale 0.625**. Check `effective_target` and `actual` in the generated
display report. `--scale 0.625` would apply the host compensation again. The
mock backend accepts `password`; it does not start a real desktop session.

The scene is editable in `lib/preset1.scene.json`. The static artwork and the
weather use the same 1920×1080 coordinate space and adapt to the scene bounds.
`lib/preset_visuals.dart` owns drawing and animation; component presentation is
in `lib/preset_components.dart`; display lettering is in `lib/weekday_lettering.dart`.

The static artwork has a separate repaint boundary. Blur is used only when
painting the cached light streaks. A single weather controller drives 170
petals and 110 rain streaks without rebuilding widgets. Its 120-second loop is
continuous across the wrap. Reduced motion, disabled ticker mode and hidden
application lifecycle states stop the controller. Clocks update once a minute.

Verification:

```sh
cd themes/preset1
fvm flutter analyze
fvm flutter test
cd ../..
akari verify-perf --theme themes/preset1
```

The performance runner requires a Wayland desktop, Sway, grim and wtype. It
creates its own nested Sway with the same display-profile resolution and host
scale compensation as `run sway`, runs a profile build through three journeys,
and records screenshots plus frame timings for dormant animation, waking,
typing, menus, errors and recovery. Engine frame numbers associate delayed
timings with the phase that actually produced the frame.

Each phase requires at least 90 samples, p95 build under 8 ms, p95 raster under
12 ms, p95 total frame latency under 33.334 ms, p95 frame interval under 25 ms,
and fewer than 20% of frames exceeding a 16.667 ms total budget. Reports and
screenshots are registered in the CLI run report. Widget tests also cover
800×600, 1280×720, 1920×1080 and 2560×1080, interrupted transitions, menu focus,
credential clearing, service recovery and stopping weather animation.

The 2026-10-09 local profile run passed all three journeys with 2,475 measured
frames at inner scale 0.625 and a Flutter render size of 2467×1580. All phases
had a 16.667 ms p95 frame interval; build p95 ranged from 0.776 to 1.443 ms,
raster p95 from 5.000 to 5.377 ms, and total latency p95 from 7.619 to 12.551 ms.
Two frames exceeded 16.667 ms (0.08%). These are measurements from the local
nested compositor, not a guarantee for other GPUs or display sizes.
