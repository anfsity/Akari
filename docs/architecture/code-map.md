---
title: Code map
description: Where to read and change each part of Akari.
---

## Repository structure

| Path | Responsibility |
| --- | --- |
| `apps/greeter/lib/app/app.dart` | Application lifetime, selected theme, shared `GreeterFeature`, and multi-display views |
| `apps/greeter/lib/infrastructure/` | D-Bus gateway (`GreeterDbusGateway`) and session preference storage |
| `packages/greeter_ui/` | Greeter business state, typed commands, and `GreeterSceneAdapter` |
| `packages/theme_sdk/` | Public `GreeterHost`, slot types, and `ThemeDefinition` contracts |
| `packages/scene_schema/` | Flutter-free scene model, codec, conditions, and component/layout/preset authoring contracts |
| `packages/scene/` | `SceneRuntime`, `ThemeBundle`, background renderers, and motion lifecycle |
| `packages/scene_codegen/` | Build-time `*.scene.json` to `*.scene.g.dart` code generator |
| `packages/greeter_components/` | Optional reusable widget set (`StandardGreeterComponents`) |
| `packages/theme_project/` | Pure Dart project validation, scene discovery, and independent theme synthesis |
| `packages/greeter_harness/` | Shared preview journeys, frame attribution, report aggregation, and Timeline summaries |
| `packages/theme_studio/` | Internal `model/`, `ui/`, `resources/`, `authoring/`, `preview/`, `timeline/`, `canvas/`, `inspector/`, and `workspace/` domains |
| `themes/` | Independent compiled theme packages (`default`, `fallback`, `preset1`) and perf suites |
| `crates/akari-backend/src/` | Rust D-Bus service, authentication actor, `greetd` transport, and session/user catalogs |
| `apps/greeter/linux/` | Native GTK/Flutter runner and multi-monitor window management |
| `crates/akari-splash/` | Standalone Rust DRM/KMS and windowed startup splash renderer |
| `packages/akari_cli/` | `akari` CLI grammar, theme host generator, and run report engine |
| `scripts/` | Toolchain bootstrap, Sway session runner, and login/harness controllers |
| `system/` | Production systemd, greetd, Sway, and VT handoff assets |
| `test/probes/` | Interactive terminal and shell completion probes |
| `test/workflows/` | Python deployment and native compositor regression tests; Dart tests live with their app/package |

## Trace common workflows

### 1. Theme build & host generation

1. `packages/akari_cli/bin/akari.dart` parses CLI flags via `packages/akari_cli/lib/src/cli/definition.dart`.
2. `packages/akari_cli/lib/src/commands/` constructs a `RunPlan` of build/verification steps, executed by `packages/akari_cli/lib/src/execution/`.
3. `packages/akari_cli/lib/src/theme/project.dart` resolves the theme manifest and builder function; `packages/akari_cli/lib/src/theme/host.dart` generates the Flutter host under `build/tool/hosts/`.
4. `scene_codegen` validates `*.scene.json` with `scene_schema` and emits `*.scene.g.dart`.

### 2. UI state update & scene rendering

1. `GreeterFeature` (`packages/greeter_ui/lib/src/feature/`) updates immutable state and notifies typed region slots.
2. `GreeterSceneAdapter` projects state into `ScenePredicate` flags and `GreeterHost` listenables.
3. `SceneRuntime` evaluates `visibleWhen` predicates per node, runs enter/exit motion transitions, and renders theme widgets inside per-node `RepaintBoundary` layers.

### 3. Authentication & session handoff

1. `apps/greeter/lib/infrastructure/dbus/greeter_dbus_gateway.dart` calls `io.akari.Greeter1` methods and listens for `Prompt` / `StateChanged` signals.
2. `crates/akari-backend/src/service.rs` and `crates/akari-backend/src/auth/actor.rs` serialize commands for the active `attempt_id`.
3. `crates/akari-backend/src/greetd/transport.rs` exchanges framed JSON over `GREETD_SOCK`, and `crates/akari-backend/src/session_launch.rs` forwards the authenticated desktop command through the user's login shell.

### 4. Multi-display & Sway sessions

- **Native multi-monitor**: `apps/greeter/linux/runner/my_application.cc` creates one fullscreen `FlView` per monitor and reports active window focus through `akari/displays`; `apps/greeter/lib/app/app.dart` shares a single `GreeterFeature` and credential controller across all views.
- **Display profiles & nested Sway**: `scripts/greetd-test/display_profile.py` validates TTY output captures, and `scripts/sway-session.py` runs nested/headless Sway sessions with scale compensation.

### 5. Theme Studio editing

- `SceneEditor` manages the active document, selection, undo/redo history, and atomic saving.
- `NodeInspectorController` validates pending inspector drafts; `node_geometry.dart` computes canvas move/resize math across transformed nodes.
- `StudioViewport` handles pan/zoom outside undo history, while `StudioAssets` imports files into the owning `theme_*` package.

## Public package entrypoints

Always import package root libraries (`theme_sdk.dart`, `scene.dart`, `scene_schema.dart`, `theme_project.dart`, `greeter_ui.dart`, `greeter_components.dart`, `akari_cli.dart`, `greeter_harness.dart`, `theme_studio.dart`). Treat `lib/src/` as private implementation detail. Browse the [API reference](../reference/api.md) for exported symbols.
