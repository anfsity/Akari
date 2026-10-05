---
title: API reference
description: Generated Dart reference for the public theme and scene packages.
---

These pages are generated from the source and its documentation comments at
the same revision as the handbook. Start with the package that owns your task:

| Package | Reference | Responsibility |
| --- | --- | --- |
| `theme_sdk` | [Browse API](/Mozais/api/dart/theme_sdk/index.html) | Theme definition, semantic host, slots, and component factory |
| `scene` | [Browse API](/Mozais/api/dart/scene/index.html) | Runtime, visual tokens, renderers, and motion |
| `scene_schema` | [Browse API](/Mozais/api/dart/scene_schema/index.html) | Document model, conditions, validation, and JSON codec |
| `greeter_components` | [Browse API](/Mozais/api/dart/greeter_components/index.html) | Optional standard visual component set |

The generated reference has its own navigation and symbol search. Use the
[component guide](../guides/components.md) for examples and the
[code map](../architecture/code-map.md) for cross-module relationships.

## Documentation ownership

Keep parameter contracts, return semantics, resource ownership, and compact
examples in `///` comments beside the public declaration. A generated signature
alone does not explain a contract. Handwritten guides explain workflows and
link to this reference rather than copying type/member catalogs.

## Local generation

```sh
cd docs/site
npm run api
```

This resolves each selected package's dependencies, runs its analyzer, and
generates static HTML with `dart doc`. It uses the repository's FVM SDK or explicit
`MOZAIS_FLUTTER_BIN` and `MOZAIS_DART_BIN` paths. Outputs live under
`docs/site/public/api/dart/` and are ignored by Git.

Backend code reference can be generated separately with rustdoc. See the
[backend code guide](../architecture/backend.md).
