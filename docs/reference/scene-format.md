---
title: Scene format
description: The version 3 authoring document schema, layout rules, style tokens, and motion specifications.
---

Scene JSON files (`*.scene.json`) define a theme's canvas, background, node hierarchy, visual styles, transforms, and visibility rules. `packages/scene_schema` validates the JSON at build time and emits typed Dart (`*.scene.g.dart`) so production builds never parse JSON at login time.

:::note
The current schema version is `3`. The decoder remains backward-compatible with versions `1` and `2`, normalizing legacy `kind`/`action` fields and preserving flat layouts.
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
- Node `id` values must be unique across the document, and `component` identifiers must be non-empty.

## Root document fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `id` | `string` | Required | Unique scene identifier |
| `version` | `1 \| 2 \| 3` | `3` | Scene schema version |
| `canvas` | Canvas object | Required | Reference dimensions, viewport fit mode, and safe-area policy |
| `background` | Background object | Required | Background renderer, asset, shader, or parameters |
| `nodes` | `Array<SceneNode>` | Required (non-empty) | Scene layers, frames, primitives, and theme components |
| `themeProperties` | `Record<string, string>` | `{}` | Theme-level preset selections (e.g., `{"palette": "ocean", "motion": "gentle"}`) validated by the theme's `presetCatalog` |
| `styleTokens` | `Record<string, SceneStyle>` | `{}` | Reusable visual style tokens referenced by `node.styleToken` |
| `guides` | `Array<SceneGuide>` | `[]` | Studio reference lines (`{"axis": "vertical" \| "horizontal", "position": 0..1}`), preserved across builds without painting in the greeter |

## Canvas

| Field | Type / Values | Default | Description |
| --- | --- | --- | --- |
| `fit` | `"cover"` \| `"contain"` \| `"reflow"` | Required | How the canvas scales to the output viewport |
| `useSafeArea` | `boolean` | `true` | Lay out nodes inside the safe-area-adjusted canvas |
| `referenceWidth` | `1..16384` | `1920` | Reference width in pixels (used by Studio pixel authoring and guide positions) |
| `referenceHeight` | `1..16384` | `1080` | Reference height in pixels (used by Studio pixel authoring and guide positions) |

## Background

| Field | Type / Values | Default | Description |
| --- | --- | --- | --- |
| `kind` | `"image"` \| `"solid"` \| `"video"` \| `"custom"` | Required | Background renderer category |
| `asset` | `string` | Omit | Bundled image or renderer asset path (e.g., `packages/theme_ocean/assets/bg.jpg`) |
| `color` | `#RRGGBB` \| `#AARRGGBB` | `"#0d151a"` | Solid fill or fallback color |
| `scrimOpacity` | `0.0..1.0` | `0.35` | Darkening scrim overlay opacity |
| `blurSigma` | `>= 0` | `0` | Canvas blur strength applied across wake transitions |
| `rendererId` | `string` | Omit | Custom renderer key registered in `ThemeBundle` |
| `parameters` | `Record<string, number>` | `{}` | Finite numeric parameters exposed as sliders in Studio and consumed by the background renderer (e.g., `refraction`, `density`, `speed`, `dispersion` in `theme_preset1`) |
| `shader` | Shader object | Omit | Runtime-owned portable fragment shader for `custom` backgrounds |

:::caution
Built-in renderers support `image`, `solid`, and `custom` backgrounds with a `shader` definition. Other `video` or `custom` backgrounds require a matching renderer in `ThemeBundle`. Asset paths must not contain `..`.
:::

### Portable fragment shaders

When `background.kind` is `"custom"`, the optional `shader` object configures a runtime-managed fragment shader without custom Dart painting code:

```json
{
  "asset": "packages/theme_ocean/assets/background.frag",
  "uniforms": [
    {"name": "resolution.x", "source": "width"},
    {"name": "resolution.y", "source": "height"},
    {"name": "time", "source": "time", "scale": 0.5, "value": 0}
  ],
  "textures": [
    {"name": "image", "asset": "packages/theme_ocean/assets/texture.png"}
  ]
}
```

- **`asset`**: Portable `.frag` resource declared under `flutter.shaders` in `pubspec.yaml`.
- **`uniforms`**: Ordered list of float bindings in compiler reflection order. Each uniform evaluates `source * scale + value` (defaults: `scale: 1`, `value: 0`). Supported `source` values:
  - `constant` (`source = 0`, evaluates to `value`)
  - `time` (elapsed seconds; fixed at `0` under reduced motion and deterministic when scrubbing the Studio timeline)
  - `width`, `height` (logical viewport dimensions)
  - `pointerX`, `pointerY` (logical pointer coordinates)
  - `dormant`, `authError` (`1.0` when active, `0.0` otherwise)
- **`textures`**: Ordered list of `sampler2D` image bindings (`{"name": "...", "asset": "..."}`).

## Nodes

| Field | Type / Values | Default | Description |
| --- | --- | --- | --- |
| `id` | `string` | Required | Unique node identifier across the document |
| `component` | `string` | Required | Component key resolved by the theme's component factory (or `"frame"` / `"sceneAsset"` for runtime-owned layers) |
| `parentId` | `string` | Omit | ID of the enclosing frame node (must reference a node with `layout`) |
| `rect` | `{ x, y, width, height }` | Required | Normalized coordinates (`0..1` relative to the canvas or parent frame's padded content area) |
| `z` | `number` | `0` | Spatial depth |
| `renderOrder` | `integer` | `0` | Paint order within the same parent (independent of `z` and `focusOrder`) |
| `focusOrder` | `integer` | `0` | Keyboard focus traversal order |
| `motion` | `"none"` \| `"fade"` \| `"fadeSlide"` \| `"fadeScale"` \| `"hoverLift"` \| `"focusGlow"` | `"none"` | Presence or interaction motion preset |
| `motionTiming` | `{ durationMs?, delayMs?, curve? }` | Inherit theme | Per-node duration (`0..60000`), delay (`0..60000`), and cubic Bezier `[x1, y1, x2, y2]` (`0..1`) |
| `tracks` | `Array<ScenePropertyTrack>` | `[]` | Keyframe tracks for `opacity`, `translateX`, `translateY`, `scale`, or `rotation` |
| `stateEffects` | `Record<ScenePredicate, "shake" \| "pulse">` | `{}` | One-shot visual effect triggered when a predicate becomes true |
| `transitions` | `Array<SceneTransitionEdge>` | `[]` | Explicit `from` -> `to` condition transition effects (`"shake"` \| `"pulse"`) |
| `visibleWhen` | Condition object / string | Omit | Declarative visibility condition (always visible when omitted) |
| `interactive` | `boolean` | `false` | Enforce minimum hit target (`minHitTarget`) and focus traversal |
| `properties` | `Record<string, string>` | `{}` | String key-value pairs interpreted by the component (or `text` for text primitives) |
| `styleToken` | `string` | Omit | Key into root `styleTokens` |
| `primitive` | `"text"` \| `"rectangle"` \| `"circle"` | Omit | Runtime-rendered shape or text layer (mutually exclusive with `asset` and `layout`) |
| `asset` | `{ path, kind?, fit?, tint? }` | Omit | Runtime-rendered image or SVG layer (mutually exclusive with `primitive` and `layout`) |
| `layout` | Frame layout object | Omit | Turns the node into a container frame (mutually exclusive with `primitive` and `asset`) |
| `sizing` | Sizing object | Proportional | Width/height mode (`proportional`, `fill`, `hug`), fixed pixel dimensions, `min`/`max` bounds, and `flex` |
| `breakpoints` | `Array<SceneBreakpoint>` | `[]` | Viewport width rules (`minWidth`) overriding `layout` and/or `sizing` |
| `transform` | Transform object | Identity | Node-local 2D/2.5D translation, scale, rotation, pivot, and perspective |

## Primitives & asset layers

Scene nodes can render portable shapes, text, or media directly through `SceneRuntime` without custom widget code in the theme's component factory:

- **Primitives (`primitive`)**: Set `primitive` to `"text"`, `"rectangle"`, or `"circle"`. Text primitives read `properties.text` and apply the node's `styleToken` typography.
- **Image & SVG layers (`asset`)**: Set `asset` to render a bundled raster image or vector graphic (`component` is typically `"sceneAsset"`):

| Field | Type / Values | Default | Description |
| --- | --- | --- | --- |
| `path` | `string` | Required | Bundled file under `assets/` or `packages/<package>/` (relative `..`, backslashes, and absolute paths are rejected) |
| `kind` | `"image"` \| `"svg"` | `"image"` | Raster image or SVG vector content |
| `fit` | `"contain"` \| `"cover"` \| `"fill"` | `"contain"` | How content fits the layer rectangle |
| `tint` | `#RRGGBB` \| `#AARRGGBB` | Omit | Optional color tint preserving source alpha |

```json
{
  "id": "logo",
  "component": "sceneAsset",
  "rect": { "x": 0.45, "y": 0.1, "width": 0.1, "height": 0.1 },
  "asset": {
    "path": "packages/theme_ocean/assets/logo.svg",
    "kind": "svg",
    "fit": "contain",
    "tint": "#ffffff"
  }
}
```

## Visual style tokens & typography

The root `styleTokens` map defines named `SceneStyle` objects shared across nodes via `styleToken`:

| Field | Type / Values | Default | Description |
| --- | --- | --- | --- |
| `fill` | `#RRGGBB` \| `#AARRGGBB` | Omit | Solid fill color or gradient start color |
| `gradientEnd` | `#RRGGBB` \| `#AARRGGBB` | Omit | Optional two-color linear gradient end color |
| `gradientAngle` | `number` (degrees) | `0` | Linear gradient angle |
| `border` | `#RRGGBB` \| `#AARRGGBB` | Omit | Border stroke color |
| `borderWidth` | `>= 0` (logical px) | `0` | Border stroke width |
| `radius` | `>= 0` (logical px) | `0` | Corner border radius |
| `shadow` | `#RRGGBB` \| `#AARRGGBB` | Omit | Drop shadow color |
| `shadowBlur` | `>= 0` (logical px) | `0` | Drop shadow blur radius |
| `shadowY` | `number` (logical px) | `0` | Drop shadow vertical offset |
| `backgroundBlur` | `>= 0` (sigma) | `0` | Backdrop blur behind the node |
| `opacity` | `0.0..1.0` | `1.0` | Layer opacity multiplier |
| `textColor` | `#RRGGBB` \| `#AARRGGBB` | Inherit | Text color override |
| `fontSize` | `>= 0` (logical px) | `0` (inherit) | Font size override |
| `fontAsset` | `string` | Omit | Bundled font asset path (loaded from bundle in production and disk in Studio) |
| `fontWeight` | `0` or `100..900` (step 100) | `0` (inherit) | Font weight override |
| `letterSpacing` | `number` (logical px) | Omit | Character spacing override |
| `lineHeight` | `> 0` (multiplier) | Omit | Line height multiplier |

Theme components with explicit typography can opt into authored `styleToken` text overrides by calling `getSceneTextStyle(context, fallback)` (used by default theme labels and clocks).

## Motion timing, keyframe tracks & state transitions

### Per-node timing (`motionTiming`)

- `durationMs` (`0..60000`, omitted inherits theme duration)
- `delayMs` (`0..60000`, default `0`)
- `curve` (`[x1, y1, x2, y2]` with coordinates in `0..1`, omitted inherits theme curve)

Delays are integrated into the presence controller so reversing an in-flight transition remains continuous. System and theme reduced-motion settings take precedence.

### Property keyframe tracks (`tracks`)

A node may define at most one track per property (`opacity`, `translateX`, `translateY`, `scale`, or `rotation` in degrees). Keyframes must have strictly increasing `timeMs` (`0..60000`, relative to `motionTiming.delayMs`), a finite `value` (`0..1` for `opacity`, `-100000..100000` for others), and an optional segment `curve` (`"linear"` default, `"easeInOut"`, or `"hold"`):

```json
{
  "property": "opacity",
  "keyframes": [
    { "timeMs": 0, "value": 0 },
    { "timeMs": 800, "value": 1, "curve": "hold" }
  ]
}
```

### State effects & transition edges (`stateEffects` & `transitions`)

- **`stateEffects`**: Maps a `ScenePredicate` name to `"shake"` or `"pulse"` (e.g., `{"isAuthError": "shake"}`), playing once when that predicate enters.
- **`transitions`**: Directed transition edges with `from` and `to` conditions (using the same `all`/`any`/`not` grammar as `visibleWhen`), `effect` (`"shake"` \| `"pulse"`), and optional `timing`. An edge fires when `from` matched the previous predicate snapshot and `to` is newly true. Explicit `transitions` take precedence over `stateEffects`.

## Frames, auto layout & breakpoints

Adding a `layout` object turns a node into a container frame (`"component": "frame"`). Child nodes set `parentId` to the frame's `id`. Ancestor visibility, opacity, and transforms apply to the entire subtree, and `renderOrder` is evaluated within each parent.

```json
{
  "id": "form",
  "component": "frame",
  "rect": { "x": 0.25, "y": 0.2, "width": 0.5, "height": 0.6 },
  "layout": {
    "direction": "column",
    "padding": 24,
    "gap": 12,
    "crossAlignment": "stretch"
  }
}
```

### Frame layout fields (`layout`)

| Field | Type / Values | Default | Description |
| --- | --- | --- | --- |
| `direction` | `"absolute"` \| `"row"` \| `"column"` | `"absolute"` | Child positioning mode (`row` and `column` compute child `x`/`y` automatically) |
| `padding` | `>= 0` (logical px) | `0` | Inner frame padding |
| `gap` | `>= 0` (logical px) | `0` | Spacing between flow children and wrapped lines |
| `mainAlignment` | `"start"` \| `"center"` \| `"end"` \| `"spaceBetween"` | `"start"` | Distribution along the main axis |
| `crossAlignment` | `"start"` \| `"center"` \| `"end"` \| `"stretch"` | `"start"` | Alignment across the cross axis |
| `wrap` | `boolean` | `false` | Wrap overflowing `row` or `column` children onto additional lines |
| `clip` | `boolean` | `false` | Clip overflowing child content to the frame bounds |

Hidden children keep their layout slots in `row` and `column` frames so authentication state changes do not shift neighboring controls.

### Node sizing & constraints (`sizing`)

- **`widthMode` / `heightMode`**: `"proportional"` (default, uses `rect`), `"fill"` (shares remaining space), or `"hug"` (shrink-wraps frame children or primitive text metrics).
- **Fixed & bounded dimensions**: Optional positive `width` / `height` (overrides proportional/fill modes), `minWidth` / `minHeight` (default `0`), and `maxWidth` / `maxHeight` (`>= min`). Interactive `minHitTarget` takes precedence over `maxWidth` / `maxHeight`.
- **`flex`**: Non-negative weight distributing remaining main-axis space in `row`/`column` frames.

### Responsive breakpoints (`breakpoints`)

A node can declare `breakpoints: [{ "minWidth": 1280, "layout": {...}, "sizing": {...} }]`. Minimum widths must be unique integers in `0..16384`. `SceneRuntime` applies the widest rule matching the current logical viewport width.

## Transforms

Unlike `rect` (which uses normalized `0..1` fractions), `transform` fields use the following units:

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
