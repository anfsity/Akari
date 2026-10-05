---
title: Frontend architecture
---

## 1. Purpose

This document defines the frontend boundary for the Akari greeter. The
authentication protocol remains owned by the Rust backend and the D-Bus
contract; the Flutter frontend owns presentation, input, and local interaction
state.

The frontend is split into four cooperating areas:

```text
Feature
  business state, typed slots, commands, recovery, D-Bus port
        |
        v
GreeterSceneAdapter
  maps semantic state to scene predicates and UI actions
        |
        v
ThemeDefinition
  theme identity, authored scene, component assembly
        |
        v
ThemeBundle
  visual tokens, background renderers, motion presets
        |
        v
SceneRuntime
  document layout, layers, transforms, motion lifecycle
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

A theme is an independent Dart package. Built-in projects live under `themes/`;
the CLI can also build a project outside this repository. A project contains:

- `*.scene.json`: authoring layout and visibility conditions.
- generated `*.scene.g.dart`: typed Dart emitted by build_runner.
- `theme.dart`: compile-time assembly of tokens and theme-owned components.
- `assets/`: package-owned images and other bundled resources.

The authoring document is versioned and contains:

```text
SceneDocument
  id
  version
  canvas: fit, safe-area policy
  background: renderer kind and trusted asset/config reference
  nodes[]

SceneNode
  id
  componentId
  normalized rect
  transform: translation, scale, rotation, pivot
  z
  renderOrder
  focusOrder
  motion preset
  visibleWhen: boolean condition over semantic predicates
  interactive
  properties
```

`z` is spatial depth. `renderOrder` is draw order. `focusOrder` is keyboard
traversal order. They are separate fields and must not be inferred from widget
insertion order.

`visibleWhen` is a small boolean condition (`all`, `any`, `not`) over a
closed vocabulary of semantic predicates such as `isDormant` or
`isAuthPrompting`. A null condition means the node is always present. The
predicate vocabulary is an enumeration over semantic greeter state; arbitrary
expressions, scripts, runtime-loaded Dart, backend types, and untrusted asset
paths are not part of the scene contract. Repository assets use `assets/...`;
theme-owned Flutter package assets use `packages/<package>/assets/...`.

Production code consumes generated Dart. Runtime JSON parsing is not part of
the application path.

The scene code is split so tooling can reuse the schema without pulling in
Flutter:

```text
packages/scene_schema   Flutter-free model, condition evaluator, JSON codec
packages/scene          runtime, theme bundle, background and motion registries
packages/scene_codegen  build_runner generator that decodes JSON and emits Dart
packages/greeter_components optional reusable semantic component set
```

`scene` re-exports the schema, so application code keeps a single
import. Scene build tooling uses the schema's codec and validation as the
authoritative implementation for parsing scene documents.

## 4. ThemeDefinition and Selection

`ThemeDefinition` is the theme package's owner of one theme's identity, generated
scene document, component assembly, and visual runtime bundle:

```text
ThemeDefinition
  id
  SceneDocument
  GreeterThemeComponents factory
  ThemeBundle
    ThemeTokens
    BackgroundRenderer registry
    SceneMotionBuilder registry
```

`ThemeBundle` contains only visual tokens and renderer registrations. The
theme definition exposes `buildScene`, which combines that theme's authored
document, visual bundle, and component factory into the generic `SceneRuntime`.
The greeter adapter supplies semantic state, host capabilities, and wake
progress; it does not assemble the scene runtime. Each theme declares its
component factory with its scene. A theme may explicitly reuse an existing
component implementation when the behavior and presentation are shared, as the
fallback theme currently does.

The reusable semantic API lives in `theme_sdk`. It exposes display-safe
slot listenables and semantic callbacks through `GreeterHost`, without giving a
theme access to the feature state owner, D-Bus, or backend objects. The greeter
adapter supplies that Host API to the selected compiled theme.

The application host receives a `ThemeBuilder` instead of selecting a theme
itself. The executable entrypoint selects the builder; the host initializes the
theme and rebuilds it with a sampled background seed when available. Background
seed extraction belongs to `ThemeDefinition`, so it does not require a catalog.

The CLI selects one project with `--theme PATH` and generates a separate host
that directly imports and injects its builder into `MyApp`. Theme discovery
reads project metadata without requiring specific theme names. Repository tests
inject builders directly; `tool/dev_main.dart` explicitly selects the default
theme for debugging. The fallback theme remains an independently selectable
minimal static theme with no blur or continuous animation.

`preview --theme PATH` builds and launches that same host with demo login state.
Each theme project owns its scenes, component assembly, tokens, and assets. A
theme may depend on SDK or explicitly shared component packages, but one theme
must not import another theme package. Its Dart and Flutter code is compiled
into the application; runtime loading of new Dart or Flutter code is not
supported.

## 5. SceneRuntime

`SceneRuntime` owns:

- normalized layout conversion and safe-area handling.
- layer ordering and 2.5D transforms.
- focus-order metadata.
- background renderer selection and fallback.
- motion component lifecycle, including enter and exit transitions.
- one repaint boundary per scene node, so each authored visual component paints
  independently from the rest of the scene.

Theme components subscribe to the typed slot that owns their content through
`SceneRegion` or another local `ListenableBuilder`. `ValueListenableBuilder`
limits which component subtree rebuilds; the node `RepaintBoundary` limits
which scene node repaints. Scene predicate notifications are handled by each
node host, so a visibility change does not rebuild the complete scene tree.

Widgets inside a scene node share that node's paint boundary. Add nested
boundaries only when profiling shows that a complex child needs independent
repainting.

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
maps display state to scene predicates, creates the narrow `GreeterHost`, and
asks the selected `ThemeDefinition` to build its scene. Theme components cannot
reach the `GreeterFeature` state owner. The theme component set maps its own
scene nodes to ordinary Flutter widgets, preserving native input, focus,
keyboard, and accessibility behavior.

The Feature projection contains no `BackgroundSlots`. Visual mood is derived by
the adapter or theme when a theme explicitly needs it. The credential response
remains in the application's shared text controller until it is sent as a command.

The Linux runner creates one fullscreen `FlView` per monitor in a single engine.
`MyApp` renders sibling views through `ViewAnchor` and `ViewCollection`, sharing
one `GreeterFeature` and credential controller. Each adapter owns its display's
focus node and animation; only the active display handles global keyboard input.
GTK reports native view focus through `akari/displays` so moving between windows
does not submit a response twice or let a passive display take credential focus.
The implicit view owns the app root and survives monitor removal by moving to a
remaining output, or staying hidden until an output reconnects. Studio requests
`AKARI_DISPLAY_MODE=single` because its editor is a single-view application.

Changing focus or attaching a view does not create another feature or backend
conversation. Account, session, authentication, dormant state, and credential
text follow the application lifetime; focus and wake animation follow each
adapter's lifetime. The multi-display Flutter test checks shared state and
single-response dispatch, while the [native display checks](../guides/testing.md#native-display-regressions)
exercise GTK view and monitor lifetime.

Returning to the dormant background with Escape preserves the authentication
attempt and its prompt. Wake resumes that same conversation. The adapter clears
local credential text on hide and restores focus on wake; it does not submit or
cancel the prompt. Explicit cancellation and client disconnect still release the
backend transaction. This prevents UI visibility changes from being counted as
failed PAM login attempts.

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

Each theme owns its performance tests and thresholds. The CLI executes declared
commands through the [theme perf protocol](../reference/theme-package.md#performance-protocol).
The default theme verifies performance with a Linux/Wayland profile integration
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
Each interaction also records the first response frame separately from its
later animation frames. Its UI-thread build/layout/paint work must stay below
5 ms in every measured cycle; raster, vsync scheduling, and normal transitions
remain covered by the frame metrics above.
Run `fvm dart run tool/akari.dart trace-perf` to capture widget build, layout,
and paint events during a separate profile run; its timings are diagnostic
and are not used by the performance gate. Set `AKARI_FLUTTER_BIN` to use a
specific Flutter SDK; the matching Dart binary is taken from the same SDK
directory.
