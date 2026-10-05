---
title: Scene format
description: The current version 2 authoring document and its validation rules.
---

The authoritative model and codec live in `packages/scene_schema`. Theme builds
validate JSON there before generating Dart. Production uses generated Dart;
it does not load authoring JSON during login.

## Minimal document

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

The example uses an identifier understood by `StandardGreeterComponents`.
A custom factory defines its own identifiers. A scene must contain at least
one node; node IDs must be unique and component identifiers non-empty.

## Canvas

| Field | Values/default | Meaning |
| --- | --- | --- |
| `fit` | `cover`, `contain`, `reflow`; required | Canvas fit policy |
| `useSafeArea` | `true` | Respect the safe-area-adjusted canvas |
| `referenceWidth` | `1920` | Reference width in pixels; 1–16384 |
| `referenceHeight` | `1080` | Reference height in pixels; 1–16384 |

Layout rectangles are normalized fractions of the available canvas, rather
than stored pixel coordinates.

## Background

| Field | Default | Meaning |
| --- | --- | --- |
| `kind` | Required | `image`, `solid`, `video`, or `custom` |
| `asset` | Absent | Bundled image or renderer configuration reference |
| `color` | `#0d151a` | Background fill |
| `scrimOpacity` | `0.35` | Scrim opacity in [0, 1] |
| `blurSigma` | `0` | Non-negative blur strength |
| `rendererId` | Absent | Optional custom renderer identifier |

Built-in renderers implement `image` and `solid`. Other kinds need an implementation
registered by the compiled theme. Asset references cannot contain `..`; image
assets use `assets/` or Flutter `packages/` paths. Theme-owned assets normally use
`packages/<package-name>/assets/...`.

Colors accept six-digit RGB or eight-digit ARGB hex strings, conventionally
written as `#RRGGBB` or `#AARRGGBB`.

## Nodes

| Field | Default | Meaning |
| --- | --- | --- |
| `id` | Required | Unique node identifier |
| `component` | Required | Identifier handled by the theme's component factory |
| `rect` | Required | Normalized `x`, `y`, `width`, and `height` |
| `z` | `0` | Spatial depth |
| `renderOrder` | `0` | Paint order |
| `focusOrder` | `0` | Keyboard traversal order |
| `motion` | `none` | Motion preset |
| `visibleWhen` | Absent | Declarative presence condition |
| `interactive` | `false` | Whether the node is interactive |
| `properties` | `{}` | Component-owned string-to-string map |
| `transform` | Identity | Node-local translation, scale, rotation, and pivot |

Rectangles require non-negative X/Y and positive width/height. Their right and
bottom edges must stay within 1. Depth, paint order, and keyboard order have
separate meanings; do not infer one from another.

Motion names are `none`, `fade`, `fadeSlide`, `fadeScale`, `hoverLift`, and
`focusGlow`. The theme registers the builders and visual timing; the runtime
owns animation lifetime.

## Transforms

| Fields | Units/default |
| --- | --- |
| `translateX`, `translateY` | Logical pixels; 0 |
| `scaleX`, `scaleY` | Multipliers; 1 |
| `rotationX`, `rotationY`, `rotationZ` | Degrees; 0 |
| `pivotX`, `pivotY` | Fractions of the laid-out node size; 0.5 |
| `perspective` | Matrix perspective coefficient; 0 |

These units differ from the rectangle's normalized canvas coordinates.

## Presence conditions

A predicate name is a condition by itself. Compose it using `all`, `any`, or
`not`; each condition object has exactly one operator. `all` and `any` accept
non-empty lists of conditions.

```json
{
  "all": [
    { "not": "isDormant" },
    { "any": ["isAuthPrompting", "isAuthError"] }
  ]
}
```

Use the `ScenePredicate` enum in the [API reference](api.md) for the complete
vocabulary. Conditions do not run arbitrary expressions or scripts. The greeter
adapter projects semantic state into predicates; themes do not derive them from
backend transport objects.

## Versions

The current version is 2. The decoder also accepts version 1, normalizing the old
`kind` and `action` vocabulary into the current component/interactivity model.
Encoding writes the current document representation. Author new documents in
version 2.
