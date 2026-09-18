# Mozais Frontend Architecture

## 1. Purpose

This document defines the frontend boundary for the Mozais greeter. The
authentication protocol remains owned by the Rust backend and the D-Bus
contract; the Flutter frontend owns presentation, input, and local interaction
state.

The frontend is split into four cooperating areas:

```text
Feature
  business state, commands, recovery, D-Bus port
        |
        v
GreeterSceneAdapter
  maps Greeter slots/effects to SceneRuntime actions
        |
        v
SceneRuntime
  document layout, layers, transforms, motion lifecycle
        |
        v
ThemeBundle
  tokens, generated SceneDocument, compiled renderers, motion presets
```

`Feature` never knows about a theme, background renderer, blur, motion preset,
or display geometry. `Theme` never owns authentication or D-Bus behavior.
`SceneRuntime` never accesses the backend directly.

## 2. Runtime Boundary

The complete runtime remains:

```text
Flutter Feature
    |
    | private/session D-Bus
    v
Rust backend bridge
    |                         \
    | greetd Unix socket       \ system D-Bus
    v                           v
greetd / PAM                systemd-logind
```

The backend owns greetd, PAM, session validation, power operations, attempt
generation, and stale-event protection. Flutter sends typed commands and
consumes typed display-safe slots.

Secrets, OTP values, PAM frames, and backend transport objects must never enter
a `SceneDocument`, `ThemeBundle`, visual context, or log.

## 3. Theme and Scene Document

A theme is a directory under `lib/themes/<name>/` containing:

- `*.scene.json`: authoring layout and bindings.
- generated `*.scene.g.dart`: typed Dart emitted by build_runner.
- `theme.dart`: compile-time assembly of tokens and optional Dart extensions.

The authoring document is versioned and contains:

```text
SceneDocument
  id
  version
  canvas: fit, safe-area policy
  background: renderer kind and trusted asset/config reference
  nodes[]
  transitions[]

SceneNode
  id
  kind
  normalized rect
  transform: translation, scale, rotation, pivot
  z
  renderOrder
  focusOrder
  motion preset
  bindings
  style
```

`z` is spatial depth. `renderOrder` is draw order. `focusOrder` is keyboard
traversal order. They are separate fields and must not be inferred from widget
insertion order.

Bindings and actions are enumerations over semantic greeter state. Arbitrary
expressions, scripts, runtime-loaded Dart, backend types, and untrusted asset
paths are not allowed.

Production code consumes generated Dart. Runtime JSON parsing is not part of
the application path.

## 4. ThemeBundle and Theme Selection

`ThemeBundle` combines:

```text
ThemeTokens
SceneDocument
BackgroundRenderer registry
SceneMotionBuilder registry
```

Theme selection is compile-time:

```text
--dart-define=MOZAIS_THEME=default
```

`default` selects the reference-like built-in theme. `fallback` is a minimal
static theme with no blur or continuous animation. An unknown theme name falls
back to `fallback`; debug builds assert to surface the configuration error.

Theme-specific custom backgrounds and motion implementations are compiled Dart
extensions registered in `theme.dart`. They are not loaded from external files
or scripts.

## 5. SceneRuntime

`SceneRuntime` owns:

- normalized layout conversion and safe-area handling.
- layer ordering and 2.5D transforms.
- focus-order metadata.
- background renderer selection and fallback.
- motion component lifecycle.
- repaint boundaries only where an animated or complex layer needs one.

Interactive nodes may be transformed, but runtime invariants still apply:

- minimum hit target size.
- safe-area fallback.
- bounded interactive rotation.
- minimum text scale.
- deterministic keyboard traversal.

Decorative nodes may use the full supported transform range. Full 3D meshes,
lighting, and arbitrary cameras are out of scope.

## 6. Background and Motion

Background renderers are compile-time implementations:

```text
image    bundled image with explicit crop and scrim policy
solid    deterministic fallback
video    future renderer behind the same contract
custom   future compiled renderer registered by a theme
```

The first implementation provides `image` and `solid`. Video and custom
renderers remain extension points until a real implementation exists.

Motion is theme-selected and runtime-executed. A theme declares presets such
as `none`, `fade`, `fadeSlide`, `fadeScale`, `hoverLift`, and `focusGlow`.
Runtime components own animation controllers, interruption, reduced-motion
behavior, and disposal. A motion component animates only its node; global
`AnimatedSwitcher` or full-screen animated overlays are not allowed.

Blur is a static background treatment or a local surface effect. A background
may declare a `blurSigma` that frosts the whole canvas once, cached with the
background repaint boundary. A glass panel may use a bounded `BackdropFilter`;
low-power or reduced-motion modes use a translucent solid fallback.
Full-screen animated blur is out of scope.

## 7. Greeter Adapter and Slots

`GreeterFeature` exposes typed region slots and commands. `GreeterSceneAdapter`
binds those slots to a generated `SceneDocument` through a typed widget
catalog. The catalog preserves ordinary Flutter input, focus, keyboard, and
accessibility behavior.

The Feature projection contains no `BackgroundSlots`. Visual mood is derived by
the adapter or theme when a theme explicitly needs it. The credential response
remains local to the Scene text controller until it is sent as a command.

## 8. Testing Policy

Tests prioritize logic, interaction, and performance over visual layout.

Unit tests cover:

- Feature reducers, commands, recovery, attempt isolation, and secret handling.
- scene document validation, theme selection, registry fallback, and generated
  code contracts.

Interaction tests cover:

- account and session selection.
- context-sensitive arrow actions.
- prompt focus, response submission, cancel, retry, and power actions.
- keyboard traversal and semantic reachability.

Runtime tests cover:

- transform clamping, safe-area fallback, render/focus order, reduced motion,
  and background failure fallback.

Tests must not assert pixel coordinates or exact visual placement. A small
number of usability invariants may assert reachability, focus order, hit target
size, and absence of overflow.

Performance is verified separately with a Linux/Wayland profile integration
run. Reports record p50/p95 build and raster frame time, rebuild/repaint scope,
and whether a settled static background schedules more than a single platform wake-up. Relative regressions
beyond the documented threshold fail the performance suite.

## 9. Implementation Order

1. Define the scene package, generated document contract, and codegen.
2. Implement SceneRuntime, transforms, background renderers, and motion.
3. Move Greeter composition behind `GreeterSceneAdapter`.
4. Add the default and fallback themes.
5. Replace layout assertions with interaction coverage.
6. Add the separate profile performance suite.
7. Build the scene editor as a later tool on the same model and runtime.
