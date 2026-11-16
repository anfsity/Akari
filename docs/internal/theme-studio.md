# Theme Studio

> [!NOTE]
> Theme Studio is actively under development. Controls, workflows, and extension points continue to evolve alongside the scene runtime.

Theme Studio is the visual Linux scene editor for compiled Akari themes. Its editor workspace uses `shadcn_flutter`, while the live canvas renders the selected theme's own components, style tokens, shaders, and assets through `SceneRuntime`.

## Launch Studio

```sh
akari run studio --theme themes/default

# Without the installed launcher:
fvm dart run packages/akari_cli/bin/akari.dart run studio --theme themes/default

# With an external theme package:
fvm dart run packages/akari_cli/bin/akari.dart run studio --theme /path/to/theme --jobs 2
```

- `studio` is a target of `akari run` (`akari run studio --help`).
- Studio always runs in `debug` mode with simulated display data and no backend or D-Bus dependency (`--mode` and `--backend` are not accepted).
- Studio compiles all built-in themes under `themes/` alongside `--theme`, allowing you to switch themes directly in the top bar.
- Saving Dart or asset files hot reloads the preview while preserving your active editor document and undo history. Use **Reload from disk** to adopt external file edits.

> [!TIP]
> If shell completion does not list `studio`, refresh your completion scripts with `akari install cli --shell zsh` (or `bash`) and re-source the environment file.

## Workspace & panels

- **Workspace modes**: Switch between **Design**, **Motion** (opens motion inspector tabs and the timeline), and **Focus** (hides side panels).
- **Collapsible & floating panels**: Toggle the left sidebar (`Ctrl+B`), right inspector (`Ctrl+Shift+B`), or fullscreen presentation mode (`Ctrl+Shift+P`, `Escape` to exit). Double-click a panel header to collapse it, click its float button to detach it into a movable/resizable window, or drag/dock panels onto either edge to form tab groups.
- **Persistent layout**: Dock positions, panel widths, floating bounds, and workspace mode are saved as user preferences without polluting scene undo history.
- **Panel density & motion**: Compose lists and inspector disclosure controls follow the editor theme's spacing density and scaling. Selection and disclosure transitions are brief and local to the panel; system reduced-motion settings skip these transitions.

## Editing workflow

1. **Choose a theme and scene**: Select a compiled theme in **Theme** and a scene in **Scenes**, click **New scene** to create a fresh artboard in the current theme, or click **Load JSON** to open any `*.scene.json` file from disk.
2. **Assemble & select layers**: Use **Compose** to toggle layout slots, apply presets, or drag basic primitives onto the canvas. Use **Layers** to inspect the front-to-back hierarchy (including hidden nodes) and **Assets** to browse or import package resources.
3. **Customize in the inspector**: Edit component properties, visual style tokens, geometry, frame auto-layout, and motion settings in the right-hand inspector.
4. **Apply & preview**: Choices and sliders preview immediately (committing a single undo step on release); text and numeric fields apply on `Enter`, blur, or **Apply to preview**. The apply button appears when there is a pending draft or validation error; otherwise the inspector shows **Synced**. Invalid drafts display an inline error while keeping the last valid scene on canvas.
5. **Undo or save**: Use **Undo** / **Redo** (`Ctrl+Z` / `Ctrl+Shift+Z`) to step through history and **Save scene** (`Ctrl+S`) to write changes atomically to the scene JSON.

### Component properties & visual styles

- **Declared component properties**: Themes can expose typed fields through [`componentCatalog`](../reference/theme-package.md#declaring-editable-component-properties). Studio renders the declared labels, text inputs, and choice dropdowns (showing declared defaults even when omitted from JSON). Undeclared properties remain editable under **Advanced properties**.
  - In `themes/default`, **Heading and caption** (`terraceLabel`) exposes **Text** and **Text style** (`Regular` / `Large`); **Date and time** (`dateTime`) exposes **Display** (`Date` / `Time`); and **Standby clock** (`terraceClock`) exposes **Clock style** (`Wide display` / `Stacked digits` / `Compact`).
- **Visual style tokens (`styleTokens`)**: Under **Visual style** in the Design inspector, configure fill color, two-color linear gradients, borders, corner radius, drop shadows, backdrop blur, opacity, and typography (font family asset, size, weight, letter spacing, and line height). Editing a node creates or updates a named `styleToken` that can be shared across multiple layers.

### Layout assembly & theme presets

- **Component library (primitives & frames)**: Under **Compose → Component library**, add reusable **Text** (`T`), **Rectangle** (`U`), **Circle**, and **Frame** (`F`) layers, or drag them horizontally onto the canvas. Double-click any text layer on the canvas to edit its text inline (`Enter` commits, `Escape` cancels).
- **Declared layout slots**: For scenes with a [`ThemeLayoutDefinition`](../reference/theme-package.md#declaring-layout-slots), **Compose** lists optional slots as checkboxes and required controls with lock icons under **Required controls**:
  - Toggling an optional slot inserts or removes its preset node (use **Undo** to recover custom edits after removal).
  - Required slots cannot be deleted. If an opened scene is missing required slots, a banner offers **Add required** to restore all missing controls in a single undo step.
- **Layout presets**: **Compose → Layout preset** switches between declared arrangements (such as `Terrace split` and `Centered column` in the default theme), updating slot positions while preserving customized properties, optional slot omissions, and custom layers.
- **Theme presets**: **Compose → Theme presets** exposes global choices declared in [`presetCatalog`](../reference/theme-package.md#declaring-theme-wide-presets) (stored in `themeProperties`). For example, `themes/default` provides palette (`Wallpaper`, `Ocean`, `Rose`, `Violet`), control material (`Airy underline`, `Frosted capsule`, `Solid`), and motion (`Terrace entrance`, `Quiet fade`, `No animation`) selectors.

### Synthesizing an independent theme

Click **Create theme**, enter a lower-case theme name and parent directory, and confirm:

- Studio exports your current valid design (including unsaved inspector edits) into a standalone `theme_<name>` package without overwriting the source theme.
- Scene files, Dart sources, assets, fonts, shaders, and licenses are copied, cross-package asset references are imported into the new package, and SDK path dependencies are rebased automatically.
- The synthesized theme is immediately selectable in the running Studio session. To run or build it standalone:

```sh
akari run studio --theme /path/to/new_theme
akari run --theme /path/to/new_theme
akari build --theme /path/to/new_theme
```

### Layers, frames & responsive layout

- **Multi-selection & grouping**: `Shift`-click nodes or drag a marquee on empty canvas space to select multiple layers (`Ctrl+A` selects all). Use the context toolbar to align, distribute equal gaps, or **Group** (`Ctrl+G`) siblings into a container frame (`Ctrl+Shift+G` ungroups plain absolute frames while preserving child positions).
- **Hierarchy reordering & reparenting**: Drag rows in **Layers** to reorder paint order within a parent, drop onto a frame row to nest a subtree, or choose **Move to scene root**.
- **Frame auto-layout**: In **Frame layout**, choose `absolute`, `row`, or `column` direction, `padding`, `gap`, main/cross alignment, line `wrap`, and overflow `clip`.
- **Sizing & viewport breakpoints**: Configure `Width mode` and `Height mode` (`proportional`, `fill`, or `hug`), fixed pixel dimensions, `min`/`max` constraints, and `flex` weights. Use **+** / **−** beside the layout selector to add or remove `minWidth` viewport breakpoints.
- **Responsive & multi-output preview**:
  - Use **Responsive** below the canvas to scrub logical viewport width/height live without modifying the authored document.
  - Use the resolution selector to apply HD, Full HD, QHD, 4K, portrait, 16:10, or ultrawide reference dimensions, or click **Compare** to view Full HD, 4K, ultrawide, and portrait outputs side by side (**Single** returns to the editing canvas).

### Coordinate units

Scene JSON always stores normalized `[0, 1]` coordinates, while the inspector can display reference pixels or percentages. On a `1920x1080` reference canvas, these represent the same rectangle:

| Field | Scene JSON | Reference Pixels | Percentage |
| --- | --- | --- | --- |
| `X` | `0.25` | `480` | `25` |
| `Y` | `0.25` | `270` | `25` |
| `Width` | `0.5` | `960` | `50` |
| `Height` | `0.25` | `270` | `25` |

Transform translations (`translateX`, `translateY`) remain in logical pixels as defined in the [Scene format](../reference/scene-format.md#transforms).

## Motion, timeline & state flow

- **Interactive preview**: Click **Preview** to play theme animations and interact with focus, hover states, and menus (**Edit canvas** returns to geometry editing). Switch between **Login** and **Dormant** states or use the scenario menu to simulate password/username prompts, submitting, rejected credentials, auth errors, account/session pickers, connecting, and service unavailability.
- **State flow & transition edges**: Open **State flow** to preview states or author directed visual transition edges (`from` condition, `to` condition, `Shake` / `Pulse` effect, and timing). Use **Design → State rules → Edit compound condition** to build nested `all` / `any` / `not` visibility rules.
- **Timeline & keyframe tracks**: Open **Timeline** to scrub or play entrance, wake, sleep, and submit-to-outcome transitions. Drag a layer's timing block to adjust delay or resize its duration. Add keyframe tracks for `opacity`, `translateX`, `translateY`, `scale`, or `rotation`, drag keyframe diamonds to retime, or double-click a keyframe to edit its value and easing (`linear`, `easeInOut`, `hold`).
- **Per-node motion & stagger**: Under **Advanced layout → Motion**, customize duration, delay, and cubic Bezier curves. With multiple layers selected, click **Stagger 100 ms** to assign sequential delays in paint order as a single undo step.

## Effects & Shader Playground

- **Background effects & parameters**: The **Effects** inspector tab adjusts background blur (`blurSigma`), scrim opacity, and any custom numeric sliders declared via `BackgroundParameter` (such as refraction, rain density, flow speed, and dispersion in `themes/preset1`).
- **Shader Playground**: Open **Effects → Shader Playground** to load a theme `.frag` shader or start from a template:
  - Click **Compile and preview** to invoke the workspace Flutter SDK's `impellerc`, inspect compiler diagnostics, and reflect `float`/vector uniforms and `sampler2D` texture slots.
  - Bind uniform slots to constants, `time`, viewport `width`/`height`, `pointerX`/`pointerY`, `dormant`, or `authError` (with `scale` and offset `value`), and bind samplers to theme image assets.
  - Click **Apply as new shader** to save the `.frag` source into the theme package, register it under `flutter.shaders`, and commit the background binding in one undo step.

## Canvas tools, rulers & shortcuts

- **Rulers & reference guides**: Toggle rulers from the bottom bar. Drag from the top or left ruler to create vertical/horizontal guides, drag guides to reposition, or double-click to remove them.
- **Smart guides & grid snapping**: Moving or resizing layers snaps edges and centers to visible layers, canvas bounds, and reference guides (6-pixel screen tolerance) while labeling nearest gaps. Toggle smart guides with the magnet button, hold `Alt` to bypass snapping temporarily, or configure grid snapping in **Settings → Grid & snapping**.

| Tool | Shortcut | Behavior |
| --- | --- | --- |
| **Move / Resize** | `V` | Drag to move `x`/`y`, or drag the 8 handles to resize `width`/`height` (hold `Shift` or toggle the lock icon to preserve aspect ratio). |
| **Hand** | `H` / `Space+drag` | Pan the viewport without selecting or modifying nodes. |
| **Scale** | `K` | Drag horizontally/vertically to adjust `scaleX`/`scaleY` (`0.01..100`) around the pivot. Use **Advanced layout -> Reset scale** to reset scale to `1`. |
| **Rotate** | `R` | Drag horizontally to rotate around the Z axis (`rotationZ`). |
| **3D Rotate** | `Shift+R` | Drag horizontally/vertically to adjust `rotationY` and `rotationX`. |

### Keyboard & mouse shortcuts

Customize bindings or mouse pan/zoom modifiers under **Settings → Shortcuts**:

| Shortcut | Action |
| --- | --- |
| `Ctrl+Mouse wheel` | Zoom around the pointer |
| `Shift+1` | Fit and recenter the canvas |
| `Arrow` / `Shift+Arrow` | Nudge selected node by `1` / `10` reference pixels |
| `T` / `U` / `F` | Create Text, Rectangle, or Frame layer |
| `Ctrl+G` / `Ctrl+Shift+G` | Group selection into a Frame / Ungroup plain Frame |
| `Ctrl+D` | Duplicate a node outside layout slots (`<id>-copy`, `<id>-copy-2`, ...) |
| `Delete` | Delete selected node (disabled for required slots and the last node) |
| `Ctrl+B` / `Ctrl+Shift+B` | Toggle left sidebar / right inspector |
| `Ctrl+Shift+P` | Toggle presentation preview mode (`Escape` exits) |
| `Ctrl+S` | Apply pending inspector fields and save scene JSON |

> [!NOTE]
> Interactive nodes enforce the compiled theme's `minHitTarget` (44 reference pixels in built-in themes), so resize handles cannot shrink an interactive node below that minimum.

## Importing & managing assets

- **Search & categories**: Filter assets by path or category (images, SVG icons, fonts, materials/textures, audio, shaders, or other files).
- **Import asset**: Copies an external file into the owning theme's `assets/` directory, registers it in `pubspec.yaml`, and copies its `packages/<theme>/assets/...` path to the clipboard.
- **Add to canvas**: Creates an independent image or SVG scene layer (`sceneAsset`) with configurable `fit` and color `tint`.
- **Use image**: Validates a raster image and sets it as the scene background (save the scene to persist).
- **Fonts**: Preview font samples at adjustable sizes and click **Apply font** to bind the font asset to the selected node's `styleToken`.
- **Package resolution**: When opening an external file via **Load JSON**, Studio locates the nearest `theme_*` package to own asset imports. Restart Studio with `--theme /path/to/theme_other` if you need to compile an external theme's custom Dart widgets.

## Code inspection & settings

- **Inspect code**: Switch the right panel from **Design** to **Inspect code** to view and copy validated **JSON** or generated **Dart** for the current **Selection** or the entire **Scene** (editing controls become read-only while inspecting code).
- **Settings**: Configure **Canvas** dimensions/fit/safe-area, **Background** image/color/blur/scrim, Studio **Appearance** (Light/Dark/System and palette), **Grid & snapping**, and **Shortcuts**.

## Troubleshooting

| Symptom | Resolution |
| --- | --- |
| Text looks stretched after resizing | Run **Advanced layout -> Reset scale**, then resize using the **Move** (`V`) handles instead of **Scale** (`K`). |
| Interactive node stops shrinking | It reached the theme's `minHitTarget` (44 px in built-in themes). |
| Canvas drag or command is blocked | Fix the validation error highlighted in the inspector first. |
| External JSON renders with the wrong components | Launch Studio with `--theme /path/to/theme` so its component factory is compiled in. |
| Imported image or SVG layer does not appear | Use **Add to canvas**; these layers and backgrounds load directly from disk. Theme-authored widgets that load their own bundle assets may still require restarting Studio. |
| Save refuses due to external file modification | Copy any needed values, then click **Reload from disk** before editing again. |

## Verification

`akari verify` runs Studio analysis and tests automatically. To run them directly from `packages/theme_studio`:

```sh
../../.fvm/flutter_sdk/bin/flutter analyze
../../.fvm/flutter_sdk/bin/flutter test
```
