---
title: Frontend architecture
description: Layering, scene runtime invariants, multi-display management, and performance budgets.
---

## 1. Layering & responsibilities

The Flutter frontend owns presentation, input, and local interaction state, while the Rust backend owns the PAM/greetd authentication protocol over D-Bus.

```text
GreeterFeature
  business state, typed slots, commands, recovery, D-Bus gateway
        |
        v
GreeterSceneAdapter
  maps semantic state to ScenePredicate flags and GreeterHost callbacks
        |
        v
ThemeDefinition
  theme identity, generated SceneDocument, component factory
        |
        v
ThemeBundle
  ThemeTokens, BackgroundRenderer registry, SceneMotionBuilder registry
        |
        v
SceneRuntime
  normalized layout, 2.5D transforms, repaint boundaries, motion lifecycle
```

Strict separation of concerns:
- **`GreeterFeature`** knows nothing about themes, backgrounds, blur, motion, or monitor geometry.
- **Themes** never access `GreeterFeature`, D-Bus, or PAM transport objects.
- **Secrets** (passwords, OTP tokens, raw PAM frames) never enter `SceneDocument`, `ThemeBundle`, or logs.

## 2. Theme packages & scene documents

Each theme is a standalone Dart package compiled into the executable:

| Package | Role |
| --- | --- |
| `packages/scene_schema` | Flutter-free `SceneDocument` model, predicate evaluator, and JSON codec |
| `packages/scene` | `SceneRuntime`, `ThemeBundle`, background/motion registries (re-exports `scene_schema`) |
| `packages/scene_codegen` | `build_runner` generator that validates `*.scene.json` and emits `*.scene.g.dart` |
| `packages/theme_sdk` | `ThemeDefinition`, `GreeterHost`, and typed slot contracts |
| `packages/greeter_components` | Optional reusable widget set (`StandardGreeterComponents`) |

### Scene node invariants

- **Explicit ordering**: `z` (spatial depth), `renderOrder` (paint order), and `focusOrder` (keyboard traversal) are independent fields and are never inferred from widget tree insertion order.
- **Declarative visibility (`visibleWhen`)**: Evaluated over a closed enum (`ScenePredicate`) using `all`, `any`, and `not`. Arbitrary scripts or runtime-loaded Dart are not supported.
- **Compile-time scenes**: Production executables use generated `*.scene.g.dart` directly without parsing JSON at login time.

## 3. `SceneRuntime` & rendering performance

`SceneRuntime` enforces fast, isolated updates across the scene tree:

- **Targeted rebuilds & repaints**: Each scene node is wrapped in a `RepaintBoundary`. Theme widgets subscribe to specific `GreeterHost` listenables via `SceneRegion`, and visibility changes are handled per node without rebuilding the entire scene tree.
- **Exit transition lifetime**: When `visibleWhen` becomes `false`, the node remains mounted (ignoring pointer/focus input) until its reverse exit animation finishes, then unmounts so timers and subscriptions stop cleanly.
- **Interactive invariants**: Transformed interactive nodes still enforce minimum hit target sizes (`minHitTarget`), safe-area fallback, and deterministic `focusOrder` traversal.

### Backgrounds, motion, and blur

- **Background renderers**: Built-in `image` and `solid` renderers (`video` and `custom` are compile-time extension points).
- **Motion presets**: `none`, `fade`, `fadeSlide`, `fadeScale`, `hoverLift`, and `focusGlow`. `SceneMotionBuilder` wraps a node using an externally driven `Animation<double>` owned by `SceneRuntime`—global `AnimatedSwitcher` or fullscreen animated overlays are not used.
- **Blur**: Static canvas `blurSigma` is cached once with the background repaint boundary. Bounded glass panels may use `BackdropFilter` with a solid fallback in reduced-motion or low-power modes.

## 4. Multi-display & dormant state behavior

### Single-engine multi-monitor views

1. The native Linux runner (`linux/runner/my_application.cc`) creates one fullscreen `FlView` per connected monitor inside a single Flutter engine.
2. `MyApp` renders sibling views via `ViewAnchor` and `ViewCollection`, sharing one `GreeterFeature` and one `credentialController`.
3. Each monitor's `GreeterSceneAdapter` owns its local focus tree and wake animation, while GTK reports the active monitor through the `akari/displays` channel so only the focused display processes global keyboard submission.
4. When a monitor is unplugged, the implicit root view migrates to a remaining output (or stays hidden until an output reconnects) without interrupting the active authentication attempt.

### Dormant state (`Escape`)

Pressing `Escape` returns the UI to the dormant background (`isDormant`) and clears local text in `credentialController`, but **does not** cancel the active backend authentication attempt. Waking the greeter resumes the same PAM prompt and restores focus, preventing UI hide/wake toggles from counting as failed PAM attempts.

## 5. Testing & performance budgets

| Test layer | Scope |
| --- | --- |
| **Unit tests** | `GreeterFeature` reducers/commands, attempt isolation, secret handling, `scene_schema` validation, and codegen contracts |
| **Interaction tests** | Account/session selection, prompt focus, submit/cancel/retry, power actions, and keyboard traversal |
| **Runtime tests** | Safe-area fallback, `renderOrder` / `focusOrder`, reduced motion, and background fallback |
| **Performance gate** (`themes/default`) | Runs in Linux/Wayland profile mode (`akari verify-perf`). Requires `>= 3` cycles, `< 5 ms` first-response UI build/layout/paint time, phase/aggregate p95 within two `16.67 ms` frame budgets, `< 20%` regression vs. baseline, and no extra platform wake-ups when static. |
