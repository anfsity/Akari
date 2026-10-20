---
title: API reference
description: Generated Dart reference for the public theme and scene packages.
---

The Dart API reference is generated from package doc comments at the same revision as the handbook.

## Public packages

| Package | API Reference | Scope |
| --- | --- | --- |
| `theme_sdk` | [Browse API](/Akari/api/dart/theme_sdk/index.html) | `ThemeDefinition`, `GreeterHost`, state slots, and component factory contracts |
| `scene` | [Browse API](/Akari/api/dart/scene/index.html) | `SceneRuntime`, `ThemeTokens`, background renderers, and motion builders |
| `scene_schema` | [Browse API](/Akari/api/dart/scene_schema/index.html) | `SceneDocument`, `ScenePredicate`, validation rules, and JSON codec |
| `greeter_components` | [Browse API](/Akari/api/dart/greeter_components/index.html) | Optional reusable greeter widgets (`StandardGreeterComponents`) |

For usage patterns and ownership boundaries, see [Develop theme components](../guides/components.md) and the [Code map](../architecture/code-map.md).

## Documentation conventions

- Document parameter contracts, return semantics, resource ownership, and short examples in `///` doc comments directly on public symbols.
- Keep cross-module tutorials in the handbook guides and link to this API reference rather than duplicating member lists.

## Generate API docs locally

```sh
cd docs/site
npm run api
```

`npm run api` resolves dependencies, runs `dart analyze`, and invokes `dart doc` using the repository's FVM SDK (or `AKARI_FLUTTER_BIN` / `AKARI_DART_BIN` overrides). Output HTML is written to `docs/site/public/api/dart/` and ignored by Git.

:::tip
To generate local documentation for the Rust backend, see the [Backend code guide](../architecture/backend.md#local-code-reference).
:::
