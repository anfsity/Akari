---
title: Code map
description: Where to read and change each part of Akari.
---

## Repository structure

| Path | Responsibility |
| --- | --- |
| `lib/app/app.dart` | Application lifetime, selected theme, shared `GreeterFeature`, and multi-display views |
| `lib/infrastructure/` | D-Bus gateway (`GreeterDbusGateway`) and session preference storage |
| `packages/greeter_ui/` | Greeter business state, typed commands, and `GreeterSceneAdapter` |
| `packages/theme_sdk/` | Public `GreeterHost`, slot types, and `ThemeDefinition` contracts |
| `packages/scene_schema/` | Flutter-free scene model, JSON codec, validation, and predicate conditions |
| `packages/scene/` | `SceneRuntime`, `ThemeBundle`, background renderers, and motion lifecycle |
| `packages/scene_codegen/` | Build-time `*.scene.json` to `*.scene.g.dart` code generator |
| `packages/greeter_components/` | Optional reusable widget set (`StandardGreeterComponents`) |
| `packages/theme_studio/` | Visual scene editor, inspector drafts, viewport, and asset importer |
| `themes/` | Independent compiled theme packages (`default`, `fallback`, `preset1`) and perf suites |
| `backend/src/` | Rust D-Bus service, authentication actor, `greetd` transport, and session/user catalogs |
| `linux/` | Native GTK/Flutter runner and multi-monitor window management |
| `splash/` | Standalone Rust DRM/KMS and windowed startup splash renderer |
| `tool/` | `akari` CLI grammar, theme host generator, and run report engine |
| `scripts/` | Toolchain bootstrap, Sway session runner, and login/harness controllers |
| `test/` | Unit, widget, CLI, and native compositor regression tests |

## Trace common workflows

### 1. Theme build & host generation

1. `tool/akari.dart` parses CLI flags via `tool/src/cli/definition.dart`.
2. `tool/src/commands/` constructs a `RunPlan` of build/verification steps, executed by `tool/src/execution/`.
3. `tool/src/theme/project.dart` resolves the theme manifest and builder function; `tool/src/theme/host.dart` generates the Flutter host under `build/tool/hosts/`.
4. `scene_codegen` validates `*.scene.json` with `scene_schema` and emits `*.scene.g.dart`.

### 2. UI state update & scene rendering

1. `GreeterFeature` (`packages/greeter_ui/lib/feature/`) updates immutable state and notifies typed region slots.
2. `GreeterSceneAdapter` projects state into `ScenePredicate` flags and `GreeterHost` listenables.
3. `SceneRuntime` evaluates `visibleWhen` predicates per node, runs enter/exit motion transitions, and renders theme widgets inside per-node `RepaintBoundary` layers.

### 3. Authentication & session handoff

1. `lib/infrastructure/dbus/greeter_dbus_gateway.dart` calls `io.akari.Greeter1` methods and listens for `Prompt` / `StateChanged` signals.
2. `backend/src/service.rs` and `backend/src/auth.rs` serialize commands for the active `attempt_id`.
3. `backend/src/greetd.rs` exchanges framed JSON over `GREETD_SOCK`, and `backend/src/session_launch.rs` forwards the authenticated desktop command through the user's login shell.

### 4. Multi-display & Sway sessions

- **Native multi-monitor**: `linux/runner/my_application.cc` creates one fullscreen `FlView` per monitor and reports active window focus through `akari/displays`; `lib/app/app.dart` shares a single `GreeterFeature` and credential controller across all views.
- **Display profiles & nested Sway**: `scripts/greetd-test/display_profile.py` validates TTY output captures, and `scripts/sway-session.py` runs nested/headless Sway sessions with scale compensation.

### 5. Theme Studio editing

- `SceneEditor` manages the active document, selection, undo/redo history, and atomic saving.
- `NodeInspectorController` validates pending inspector drafts; `node_geometry.dart` computes canvas move/resize math across transformed nodes.
- `StudioViewport` handles pan/zoom outside undo history, while `StudioAssets` imports files into the owning `theme_*` package.

## Public package entrypoints

Always import package root libraries (`theme_sdk.dart`, `scene.dart`, `scene_schema.dart`, `greeter_components.dart`). Treat `lib/src/` as private implementation detail. Browse the [API reference](../reference/api.md) for exported symbols.
