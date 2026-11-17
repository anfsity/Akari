---
title: System overview
description: The ownership boundaries between themes, the frontend, and the backend.
---

```mermaid
flowchart TD
    Project[Theme package] --> Codegen[Scene code generation]
    Codegen --> Host[Generated Flutter host]
    Project --> Host
    Host --> Feature[Greeter feature]
    Feature --> Adapter[Scene adapter]
    Adapter --> Runtime[Theme definition and Scene runtime]
    Feature --> Bridge[Rust D-Bus bridge]
    Bridge --> Greetd[greetd and PAM]
    Bridge --> Logind[systemd-logind]
```

```mermaid
flowchart TD
    Schema[scene_schema: pure Dart contracts] --> Codegen[scene_codegen]
    Schema --> Project[theme_project: discovery and synthesis]
    Project --> CLI[akari_cli: pure Dart tools]
    Project --> Studio[theme_studio: internal editing domains]
    Schema --> Scene[scene: Flutter runtime]
    Scene --> SDK[theme_sdk: public theme API]
    SDK --> Components[greeter_components]
    SDK --> UI[greeter_ui]
    SDK --> Studio
    Components --> Themes[Independent theme packages]
    SDK --> Themes
    UI --> App[apps/greeter: native runner and D-Bus]
    UI --> Harness[greeter_harness: preview and metrics]
```

In-repository apps, shared packages, and built-in themes share a root Dart Pub Workspace (`pubspec.yaml` and `pubspec.lock`), while external theme packages and generated `build/tool/hosts/*` resolve path dependencies independently without workspace membership. `theme_sdk` re-exports the scene runtime and authoring contracts so theme packages only need to depend on the SDK and scene libraries.

## Ownership boundaries

| Layer | Owner | Responsibilities |
| --- | --- | --- |
| **Build boundary** | Theme package + CLI (`packages/akari_cli/`) | A theme package owns its `*.scene.json`, visual tokens, assets, and widgets. The CLI selects one theme, generates `*.scene.g.dart`, and creates a compiled Flutter host importing that theme's builder. |
| **Frontend boundary** | Flutter app + `greeter_ui` + `scene` | `GreeterFeature` owns business state, credential controllers, and typed commands. `GreeterSceneAdapter` projects semantic state into predicates (`ScenePredicate`) and `GreeterHost` slots. `SceneRuntime` handles normalized layout, 2.5D transforms, and enter/exit animations. |
| **Backend boundary** | Rust bridge (`crates/akari-backend/`) | Owns the `greetd` Unix socket, PAM conversation, attempt tokens (`attempt_id`), session catalog validation, and `systemd-logind` power actions. Exposes the [D-Bus contract](../reference/dbus.md) over a private session bus. |

:::note
Themes never communicate with `greetd`, PAM, or D-Bus directly. They render display-safe state from `GreeterHost` and invoke semantic callbacks.
:::

## Where to go next

- [Code map](code-map.md): Locate every package, runner, and tool in the repository.
- [Frontend architecture](frontend.md): Understand how `GreeterFeature`, `ThemeDefinition`, and `SceneRuntime` cooperate.
- [Backend code guide](backend.md): Explore the Rust authentication actor and session launcher.
