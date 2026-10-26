---
title: Scene format
description: The current version 2 authoring document and its validation rules.
---

Scene JSON files (`*.scene.json`) define a theme's canvas, background, nodes, transforms, and visibility rules. `packages/scene_schema` validates the JSON at build time and generates typed Dart (`*.scene.g.dart`) for production.

:::note
Current schema version is `2`. The decoder still accepts version `1` and normalizes legacy `kind`/`action` fields, but all new scenes should be authored in version `2`.
:::

## Minimal example

```json
{
  "id": "ocean",
  "version": 2,
  "canvas": {
    "fit": "contain",
    "useSafeArea": true,
    "referenceWidth": 1920,
    "referenceHeight": 1080
  },
  "background": {
    "kind": "solid",
    "color": "#0d151a"
  },
  "nodes": [
    {
      "id": "clock",
      "component": "dateTime",
      "rect": { "x": 0.3, "y": 0.4, "width": 0.4, "height": 0.2 },
      "properties": { "variant": "time" }
    }
  ]
}
```

- A scene must contain at least one node.
- Node `id` values must be unique within the document, and `component` identifiers must be non-empty.

## Theme preset selections

The optional root `themeProperties` object stores string values interpreted by
the theme, such as `{"palette": "nord", "motion": "gentle"}`. The theme declares
which settings and choices it supports. These values are preserved by scene
editing and compiled into generated Dart alongside the nodes; they are not
Studio appearance preferences. An omitted object uses the theme's defaults.

## Canvas

| Field | Type / Values | Default | Description |
| --- | --- | --- | --- |
| `fit` | `"cover"` \| `"contain"` \| `"reflow"` | Required | How the canvas scales to the output viewport |
| `useSafeArea` | `boolean` | `true` | Lay out nodes inside the safe-area-adjusted canvas |
| `referenceWidth` | `1..16384` | `1920` | Reference width in pixels (used by Studio pixel authoring) |
| `referenceHeight` | `1..16384` | `1080` | Reference height in pixels (used by Studio pixel authoring) |

## Background

| Field | Type / Values | Default | Description |
| --- | --- | --- | --- |
| `kind` | `"image"` \| `"solid"` \| `"video"` \| `"custom"` | Required | Background renderer category |
| `asset` | `string` | Omit | Bundled image or renderer asset path (e.g., `packages/theme_ocean/assets/bg.jpg`) |
| `color` | `#RRGGBB` \| `#AARRGGBB` | `"#0d151a"` | Solid fill or fallback color |
| `scrimOpacity` | `0.0..1.0` | `0.35` | Darkening scrim overlay opacity |
| `blurSigma` | `>= 0` | `0` | Static canvas blur strength |
| `rendererId` | `string` | Omit | Custom renderer key registered in `ThemeBundle` |

:::caution
Built-in renderers support `image` and `solid`. Using `video` or `custom` requires registering a matching renderer in the theme's `ThemeBundle`. Asset paths must not contain `..`.
:::

## Nodes

| Field | Type / Values | Default | Description |
| --- | --- | --- | --- |
| `id` | `string` | Required | Unique node identifier |
| `component` | `string` | Required | Component key resolved by the theme's component factory |
| `rect` | `{ x, y, width, height }` | Required | Normalized canvas coordinates (`x >= 0`, `y >= 0`, `width > 0`, `height > 0`, `x + width <= 1`, `y + height <= 1`) |
| `z` | `number` | `0` | Spatial depth |
| `renderOrder` | `integer` | `0` | Paint order (independent of `z` and `focusOrder`) |
| `focusOrder` | `integer` | `0` | Keyboard focus traversal order |
| `motion` | `"none"` \| `"fade"` \| `"fadeSlide"` \| `"fadeScale"` \| `"hoverLift"` \| `"focusGlow"` | `"none"` | Presence/interaction motion preset |
| `visibleWhen` | Condition object / string | Omit | Declarative visibility condition (always visible when omitted) |
| `interactive` | `boolean` | `false` | Enforce minimum hit target and focus traversal |
| `properties` | `Record<string, string>` | `{}` | String key-value pairs interpreted by the component |
| `transform` | Transform object | Identity | Node-local translation, scale, rotation, and pivot |

## Transforms

Unlike `rect` (which uses normalized `0..1` canvas fractions), `transform` fields use the following units:

| Field | Unit | Default |
| --- | --- | --- |
| `translateX`, `translateY` | Logical pixels | `0` |
| `scaleX`, `scaleY` | Multiplier | `1` |
| `rotationX`, `rotationY`, `rotationZ` | Degrees | `0` |
| `pivotX`, `pivotY` | Fraction of node size (`0..1`) | `0.5` |
| `perspective` | Matrix perspective coefficient | `0` |

## Presence conditions (`visibleWhen`)

A condition can be a single `ScenePredicate` name or a boolean combination using `all`, `any`, or `not` (each condition object may contain only one operator):

```json
{
  "all": [
    { "not": "isDormant" },
    { "any": ["isAuthPrompting", "isAuthError"] }
  ]
}
```

See `ScenePredicate` in the [API reference](api.md) for all supported predicate names.

:::tip[Handling the dormant state]
Pressing `Escape` enters `isDormant` without cancelling the active PAM prompt, so authentication predicates (`isAuthPrompting`, `isAuthError`) can remain true while `isDormant` is also true. Gate interactive login controls with `{ "not": "isDormant" }` if they should hide when dormant.
:::
