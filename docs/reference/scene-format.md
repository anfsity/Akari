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
  "version": 3,
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

Optional root `guides` stores Studio reference lines as
`{"axis":"vertical"|"horizontal", "position":0..1}`. Positions are canvas
fractions, so guides follow reference-resolution changes. They compile with the
document for lossless authoring round trips and do not paint in the greeter.

| Field | Type / Values | Default | Description |
| --- | --- | --- | --- |
| `fit` | `"cover"` \| `"contain"` \| `"reflow"` | Required | How the canvas scales to the output viewport |
| `useSafeArea` | `boolean` | `true` | Lay out nodes inside the safe-area-adjusted canvas |
| `referenceWidth` | `1..16384` | `1920` | Reference width in pixels (used by Studio pixel authoring) |
| `referenceHeight` | `1..16384` | `1080` | Reference height in pixels (used by Studio pixel authoring) |

## Background

`background.parameters` is an optional map of finite numbers owned by the
compiled renderer. Theme renderers declare `BackgroundParameter` metadata for
Studio sliders, including labels, bounds, and defaults. Values round-trip and
compile with the scene. Preset1 exposes refraction (`0..3`), rain density
(`0..2`), flow speed (`0.1..4`), and color dispersion (`0..4`); omitted values
retain the original appearance. Renderers bound values when resolving their
parameter contracts.

| Field | Type / Values | Default | Description |
| --- | --- | --- | --- |
| `kind` | `"image"` \| `"solid"` \| `"video"` \| `"custom"` | Required | Background renderer category |
| `asset` | `string` | Omit | Bundled image or renderer asset path (e.g., `packages/theme_ocean/assets/bg.jpg`) |
| `color` | `#RRGGBB` \| `#AARRGGBB` | `"#0d151a"` | Solid fill or fallback color |
| `scrimOpacity` | `0.0..1.0` | `0.35` | Darkening scrim overlay opacity |
| `blurSigma` | `>= 0` | `0` | Static canvas blur strength |
| `rendererId` | `string` | Omit | Custom renderer key registered in `ThemeBundle` |
| `shader` | Shader object | Omit | Runtime-owned fragment shader for `custom` backgrounds |

:::caution
Built-in renderers support `image`, `solid`, and `custom` with a shader definition. Other `video` or `custom` backgrounds require a matching theme renderer. Asset paths must not contain `..`.
:::

### Portable fragment shaders

For `kind: "custom"`, optional `shader` supplies `asset` (a portable `.frag`
resource registered in `flutter.shaders`), `uniforms`, and optional `textures`.
Float/vector components occupy consecutive slots in compiler reflection order;
texture samplers use a separate ordered table. Binding names must be unique.

```json
{
  "asset": "packages/theme_ocean/assets/background.frag",
  "uniforms": [
    {"name": "resolution.x", "source": "width"},
    {"name": "resolution.y", "source": "height"},
    {"name": "time", "source": "time", "scale": 0.5, "value": 0}
  ],
  "textures": [{"name": "image", "asset": "packages/theme_ocean/assets/texture.png"}]
}
```

Sources are `constant`, `time` (seconds), `width`, `height`, `pointerX`,
`pointerY` (logical pixels), `dormant`, or `authError` (0/1). The float is
`source * scale + value`, with defaults `scale: 1`, `value: 0`; constants use a
zero source. Numbers must be finite. The runtime owns shader/texture handles and
the clock. Scrubbing supplies deterministic time; reduced motion fixes time at
zero. Blur/scrim apply as they do to images. Studio reflects the compiler output
and generates the binding order rather than parsing GLSL declarations itself.

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

## Image and SVG layers

Nodes can declare `primitive: "text" | "rectangle" | "circle"` for portable
runtime-owned content. Text uses `properties.text`; all primitives use the same
style tokens, layout, visibility, and motion as theme components. A primitive,
asset, and frame layout are mutually exclusive. Studio can add primitives
repeatedly and drag them into scenes without a theme-declared layout slot.

An optional node `asset` object renders an image or SVG directly through the
scene runtime. These nodes bypass the theme's component factory; Studio uses
`sceneAsset` as their component identifier. They support the same geometry,
styles, motion, visibility, and frame nesting as other layers. A node cannot
declare both `asset` and `layout`.

| Field | Type / Values | Default | Description |
| --- | --- | --- | --- |
| `path` | `string` | Required | Bundled file under `assets/` or `packages/<package>/`; absolute paths, backslashes, `..`, and directory paths are rejected |
| `kind` | `"image"` \| `"svg"` | `"image"` | Raster image or SVG content |
| `fit` | `"contain"` \| `"cover"` \| `"fill"` | `"contain"` | How content fits the layer rectangle |
| `tint` | `#RRGGBB` \| `#AARRGGBB` | Omit | Optional color override preserving source alpha |

```json
{
  "id": "logo", "component": "sceneAsset",
  "rect": {"x": 0.45, "y": 0.1, "width": 0.1, "height": 0.1},
  "asset": {"path": "packages/theme_ocean/assets/logo.svg",
            "kind": "svg", "fit": "contain", "tint": "#ffffff"}
}
```

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

Typography also supports `fontAsset` (a portable asset path), `fontWeight`
(`100..900` in steps of 100; `0` inherits), optional finite `letterSpacing`, and
optional positive `lineHeight` as a font-size multiplier. Omitted values inherit
the theme. Referenced fonts load from the bundle in production and from disk in
Studio; independent theme creation copies and rewrites their paths. Components
with explicit styles can use `getSceneTextStyle` to receive these overrides.

## Motion timing

Nodes may also declare `stateEffects`, for example
`{"isAuthError": "shake"}`. Known semantic predicates trigger `shake` or `pulse`
once on entry; unrelated updates do not restart them. Responses use node timing,
work on entire frames, honor reduced motion, and can be sampled on the timeline.
When several rules enter together, the last authored rule wins. These are visual
responses; the authentication feature continues to own the actual state machine.

Optional node `motionTiming` stores `durationMs` (omitted inherits the theme),
`delayMs` (default `0`), and optional cubic Bezier `curve: [x1,y1,x2,y2]`.
Duration and delay accept integer `0..60000` milliseconds; all four curve
coordinates use `0..1`. Omitting the curve inherits theme easing. Delays are
part of the presence controller, so reversing an in-flight transition stays
continuous. Studio's timeline samples the same progress function used live.
System and theme reduced-motion policies still take precedence.

### Property tracks

Optional node `tracks` stores at most one track per property: `opacity`,
`translateX`, `translateY`, `scale`, or `rotation` (degrees). Each track has one or
more strictly increasing keyframes with integer `timeMs` in `0..60000`, a finite
`value` in `-100000..100000` (opacity `0..1`), and optional `curve`: `linear`
(default), `easeInOut`, or `hold`. A frame's curve governs the segment after it.
Times are relative to the node's motion delay. Values clamp to endpoint frames
outside their range. The existing presence controller also owns track playback;
long tracks extend its duration without stretching the presence preset.

```json
{"property": "opacity", "keyframes": [
  {"timeMs": 0, "value": 0},
  {"timeMs": 800, "value": 1, "curve": "hold"}
]}
```

### Visual transition edges

Optional node `transitions` stores edges with required `from` and `to` conditions
(the same All/Any/Not vocabulary as `visibleWhen`), `effect: "shake" | "pulse"`,
and optional `timing` using the `motionTiming` format. An edge fires when its
source matched the previous predicate snapshot and its target is newly true.
The last matching explicit edge wins over simple `stateEffects` entries. Omitted
timing inherits node timing. Edges control presentation only; they cannot change
the authentication state machine.

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

### Constraints, content fitting, and breakpoints

`sizing.widthMode` / `heightMode` accept `proportional` (default), `fill`, or
`hug`. Fixed dimensions override proportional/fill dimensions; explicit `flex`
owns distribution on a flow's main axis. Fill otherwise shares remaining main
space, or fills available space on other axes. `minWidth` / `minHeight` default
to 0; optional positive `maxWidth` / `maxHeight` must be at least the minimum.
Interactive hit-target minimums take precedence over maxima. Hug is supported
for frames and primitive text. Text uses actual font metrics; frames measure
child bounds and wrapped flow lines. Set `layout.wrap: true` to wrap row/column
children with the declared gap.

Node `breakpoints` is a list of `{minWidth, layout?, sizing?}` overrides. Minimum
widths must be unique within `0..16384`. Each rule must override layout or sizing;
only frames can override layout. The widest matching rule wins. Matching uses
the logical viewport supplied to `SceneRuntime`, independently of physical pixel
density. The same calculator resolves production rectangles and Studio selection
geometry.

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
