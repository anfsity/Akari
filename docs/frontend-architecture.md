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

A theme is a directory under `packages/mozais_greeter_ui/lib/themes/<name>/`
containing:

- `*.scene.json`: authoring layout and visibility conditions.
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
  visibleWhen: boolean condition over semantic predicates
  style
```

`z` is spatial depth. `renderOrder` is draw order. `focusOrder` is keyboard
traversal order. They are separate fields and must not be inferred from widget
insertion order.

`visibleWhen` is a small boolean condition (`all`, `any`, `not`) over a
closed vocabulary of semantic predicates such as `isDormant` or
`isAuthPrompting`. A null condition means the node is always present. The
vocabulary and actions are enumerations over semantic greeter state; arbitrary
expressions, scripts, runtime-loaded Dart, backend types, and untrusted asset
paths are not allowed.

Production code consumes generated Dart. Runtime JSON parsing is not part of
the application path.

The scene code is split so tooling can reuse the schema without pulling in
Flutter:

```text
packages/mozais_scene_schema   Flutter-free model, condition evaluator, JSON codec
packages/mozais_scene          runtime, theme bundle, background and motion registries
packages/mozais_scene_codegen  build_runner generator that decodes JSON and emits Dart
packages/mozais_scene_editor   desktop editor over the same model and runtime
```

`mozais_scene` re-exports the schema, so application code keeps a single
import. The generator and the editor share the schema's codec and validation
instead of each parsing the document format.

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
- motion component lifecycle, including enter and exit transitions.
- repaint boundaries only where an animated or complex layer needs one.

A node whose `visibleWhen` becomes false stays mounted until its exit
transition settles and is then unmounted, so stateful content such as the
clock timer stops. Exiting nodes do not receive pointer or focus input.

Interactive nodes may be transformed, but runtime invariants still apply:

- minimum hit target size.
- safe-area fallback.
- deterministic keyboard traversal.

Nodes may use the full supported transform range. Full 3D meshes,
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
Each `SceneMotionBuilder` wraps a child with an externally driven
`Animation<double>` and never owns a controller. Runtime components own
controllers, interruption, reduced-motion behavior, and disposal, driving the
same animation forward on mount and in reverse on exit. A motion component
animates only its node; global `AnimatedSwitcher` or full-screen animated
overlays are not allowed.

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

- safe-area fallback, render/focus order, reduced motion, and background
  failure fallback.

Tests must not assert pixel coordinates or exact visual placement. A small
number of usability invariants may assert reachability, focus order, hit target
size, and absence of overflow.

Performance is verified separately with a Linux/Wayland profile integration
run. Reports record p50/p95 and maximum build, raster, vsync overhead, and total
frame time by interaction phase, count frames beyond the 16.67 ms budget,
validate phase matching and sample availability, and check whether a settled
static background schedules more than a single platform wake-up. The gate
rejects phases with fewer than five matched samples, more than 20% unmatched
frames, reports with fewer than three measurement cycles, per-phase and
aggregate interaction p95 total spans over two 16.67 ms frame budgets, and
build or raster p50/p95 regressions above 20% from baseline. It also rejects
results when a majority of independent cycles have more than 20% of interaction
frames beyond the 16.67 ms budget.
Run `bash scripts/trace-perf-builds.sh` to capture widget build, layout, and
paint events during startup and first wake in a separate profile run; its
timings are diagnostic and are not used by the performance gate. Set
`MOZAIS_FLUTTER_BIN` to use a specific Flutter SDK; the matching Dart binary
is taken from the same SDK directory.

## 9. Implementation Order

1. Define the scene package, generated document contract, and codegen.
2. Implement SceneRuntime, transforms, background renderers, and motion.
3. Move Greeter composition behind `GreeterSceneAdapter`.
4. Add the default and fallback themes.
5. Replace layout assertions with interaction coverage.
6. Add the separate profile performance suite.
7. Build the scene editor as a tool on the same model and runtime
   (`packages/mozais_scene_editor`).
