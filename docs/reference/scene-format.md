---
title: Scene format
description: The current version 3 authoring document and its validation rules.
---

Scene JSON files (`*.scene.json`) define a theme's canvas, background, nodes, transforms, and visibility rules. `packages/scene_schema` validates the JSON at build time and generates typed Dart (`*.scene.g.dart`) for production.

:::note
Current schema version is `3`. The decoder accepts versions `1` and `2`, normalizes legacy `kind`/`action` fields, and preserves existing flat layouts.
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

## Visual style tokens

The optional root `styleTokens` object maps names to `SceneStyle` values. A node
references a style with `styleToken`; missing references are rejected. Styles
support ARGB `fill`, optional `gradientEnd`, `gradientAngle` in degrees, `border`,
`borderWidth`, `radius`, `shadow`, `shadowBlur`, `shadowY`, `backgroundBlur`,
optional `textColor`, `fontSize` (`0` inherits), and `opacity` (`0..1`). Dimensions
are logical pixels. Nodes sharing a token update together. Omitted style tokens
preserve the theme's visuals. Explicit component typography can opt into authored
overrides using `getSceneTextStyle(context, fallback)`; Terrace labels and clocks
do so. Other components retain their own explicit text styles.

## Motion timing

Optional node `motionTiming` stores `durationMs` (omitted inherits the theme),
`delayMs` (default `0`), and optional cubic Bezier `curve: [x1,y1,x2,y2]`.
Duration and delay accept integer `0..60000` milliseconds; all four curve
coordinates use `0..1`. Omitting the curve inherits theme easing. Delays are
part of the presence controller, so reversing an in-flight transition stays
continuous. Studio's timeline samples the same progress function used live.
System and theme reduced-motion policies still take precedence.

## Frames and auto layout

Set a node's `layout` to create a runtime-owned frame. Its `component` may be
`frame`; it does not call the theme component factory. Other nodes reference
the frame with `parentId`. IDs remain document-wide, and missing/non-frame
parents and cycles are rejected. Paint order applies within each parent.
Ancestor visibility and transforms apply to the entire subtree.

`layout.direction` accepts `absolute` (default), `row`, or `column`. `padding`
and `gap` are non-negative logical pixels. `mainAlignment` accepts `start`,
`center`, `end`, or `spaceBetween`; `crossAlignment` accepts `start`, `center`,
`end`, or `stretch`. Set `clip: true` to clip overflowing children.

Child `rect` coordinates are relative to the parent's padded content area.
Row/column layout supplies positions instead of `rect.x/y`. Optional `sizing`
provides positive fixed `width`/`height` in logical pixels and a non-negative
`flex` weight. Flex children share remaining main-axis space after fixed sizes,
spacing, and minimum interactive hit targets. Hidden children retain their
layout slots so authentication transitions do not move neighboring controls.
Fixed content can overflow a small frame; clipping is an explicit frame policy.

```json
{
  "id": "form", "component": "frame",
  "rect": {"x": 0.25, "y": 0.2, "width": 0.5, "height": 0.6},
  "layout": {"direction": "column", "padding": 24, "gap": 12,
             "crossAlignment": "stretch"}
}
```

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
