---
title: Code map
description: Where to read and change each part of Akari.
---

## Repository map

| Path | Responsibility |
| --- | --- |
| `lib/app/app.dart` | Application lifetime, selected theme, shared feature, and displays |
| `lib/infrastructure/` | D-Bus gateway and session preference storage |
| `packages/greeter_ui/` | Greeter business state, typed commands, and scene adapter |
| `packages/theme_sdk/` | Public theme host, slot types, and theme assembly |
| `packages/scene_schema/` | Flutter-free scene model, codec, and conditions |
| `packages/scene/` | Layout, transforms, background renderers, and motion runtime |
| `packages/scene_codegen/` | Build-time scene JSON to Dart generation |
| `packages/greeter_components/` | Optional reusable visual component set |
| `packages/theme_studio/` | Scene authoring, inspector drafts, editor viewport, and scene-owned assets |
| `themes/` | Independent compiled theme projects and theme-specific tests |
| `backend/src/` | D-Bus service, authentication, greetd transport, and catalogs |
| `linux/` | Native Flutter runner and display integration |
| `tool/` | CLI grammar, project discovery, generated hosts, and execution reports |
| `scripts/` | Toolchain setup and Linux session/test support |
| `test/` | Application, CLI, infrastructure, and native workflow tests |

## Follow a theme build

Start at `tool/akari.dart`. `tool/src/cli_definition.dart` owns the shared
command grammar. `theme_project.dart` resolves the package and builder;
`command_plans.dart` describes execution; `theme_host.dart` creates the selected
host. The scene builder delegates validation to `scene_schema` and emits Dart
that the theme imports.

## Follow a UI update

Read `GreeterFeature` and its state/commands under `packages/greeter_ui/lib/feature/`.
Then read `GreeterSceneAdapter`, `GreeterHost`, and the theme's component factory.
Slots project business state into visual regions; scene predicates control
presence. `SceneRuntime` handles layout and motion independently of authentication.

## Follow authentication

Start at `lib/infrastructure/dbus/greeter_dbus_gateway.dart`, then
`backend/src/service.rs` and `backend/src/greetd.rs`. The service owns serialized
authentication processing and attempt isolation. The transport owns protocol
frames. See the [backend guide](backend.md) and [D-Bus contract](../reference/dbus.md).

## Follow a Studio edit

`SceneEditor` owns the current document, selection, undo/redo, and conflict-aware
saving. `NodeInspectorController` owns pending field values; `node_geometry.dart`
calculates movement and resizing with the runtime's layout and transforms.
`StudioViewport` owns zoom and pan separately from document history.
`StudioAssets` resolves the loaded scene's theme package and owns its imports.
The compiled preview keeps using the selected theme's component factory.

## Follow a display session

`linux/runner/my_application.cc` owns monitor windows and native focus reporting;
`lib/app/app.dart` owns their shared feature and credential controller.
`scripts/greetd-test/display_profile.py` validates and resolves login captures.
`scripts/sway-session.py` owns the nested/headless compositor, effective output
checks, and screenshots. The [display guide](../guides/display-testing.md)
connects these paths to manual and native regression workflows.

## Public entrypoints

Import `theme_sdk.dart`, `scene.dart`, `scene_schema.dart`, or
`greeter_components.dart` from their packages. Treat `lib/src/` as implementation
detail and use the [generated API reference](../reference/api.md) to inspect the
exposed surface.

Studio is still being developed. Its internal notes and future proposals stay
in the repository and are excluded from the published documentation collection.
