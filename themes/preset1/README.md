# Preset 1 — Life / Death (`theme_preset1`)

`theme_preset1` is a procedural canvas and fragment-shader theme built around a diagonal light/dark composition. The background, cherry branches, blossoms, light streaks, rain, rising petals, and angular weekday lettering are rendered on Flutter's `Canvas`, while wet glass refraction and flowing water are driven by a fragment shader.

## Interaction & layout

- **Dormant & waking states**: Dormant mode displays a mirrored clock composition. Waking reveals the login controls directly across the artwork—account identity in the pale upper-left field, session selection on the dark right side, borderless credential input below the branch, and a continuation arrow—without a traditional card panel.
- **Keyboard & focus**: `Escape` closes an open popup menu first, or returns to dormant mode and clears typed credentials. `Tab` traverses `account → session → credential → continue → power`.
- **Proportional scaling**: Controls scale relative to their authored scene bounds (`1920×1080` reference space), keeping typography and icons proportional across monitor resolutions and DPI scales.

## Architecture & shader pipeline

| File | Responsibility |
| --- | --- |
| `lib/preset1.scene.json` | Authored scene layout, visibility predicates, and default background parameters |
| `lib/theme.dart` | `buildPreset1Theme` entrypoint, `ThemeTokens`, and `BackgroundParameter` declarations |
| `lib/preset_visuals.dart` | Procedural artwork rasterization, particle weather simulation, and shader painting |
| `lib/preset_components.dart` | Dispersed account, session, credential, status, and power widgets |
| `lib/weekday_lettering.dart` | Angular custom-painted weekday typography |
| `lib/shaders/wet_surface.frag` | Wet glass refraction, chromatic dispersion, and diagonal water current (`packages/theme_preset1/shaders/wet_surface.frag`) |

- **Cached background raster**: Smooth gradients and blurred light streaks are rasterized once into a `960×540` texture (under 2 MiB of RGBA pixels) shared by the static background and the water shader, while blossoms, lettering, and particles render at native display resolution.
- **Continuous weather loop**: A single weather controller drives 170 petals, 630 fine raindrops, 90 distant streaks, sliding glass drops, and the diagonal water current across a seamless 120-second loop without rebuilding widgets. Reduced motion, disabled ticker mode, and hidden lifecycle states pause the controller automatically.
- **Editable shader parameters**: Exposes `refraction` (`0..3`), `density` (`0..2`), `speed` (`0.1..4`), and `dispersion` (`0..4`) to Theme Studio's **Effects** inspector.

## Running & verification

Run inside nested Sway from the repository root:

```sh
akari run sway --theme themes/preset1 --display-profile reference --mode profile
```

Run static analysis, widget/shader tests, and the automated Sway performance gate:

```sh
cd themes/preset1
fvm flutter analyze
fvm flutter test
cd ../..
akari verify-perf --theme themes/preset1
```

The performance gate launches an isolated nested Sway session in profile mode, runs three interactive login journeys, and verifies frame build/raster/interval budgets (`>= 90` samples per phase, p95 build `< 8 ms`, p95 raster `< 12 ms`, p95 total latency `< 33.334 ms`, p95 interval `< 25 ms`, and `< 20%` of frames over `16.667 ms`).
