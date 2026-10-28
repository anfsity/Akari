# Theme Studio

> [!NOTE]
> Theme Studio is actively under development. Controls, workflows, and extension points are evolving as visual editing capabilities are added.

Theme Studio is the visual Linux scene editor for compiled Akari themes. Its editor UI uses `shadcn_flutter`, while the live canvas renders the selected theme's own components, tokens, and assets through `SceneRuntime`.

## Launch Studio

```sh
akari run studio --theme themes/default

# Without the installed launcher:
fvm dart run tool/akari.dart run studio --theme themes/default

# With an external theme package:
fvm dart run tool/akari.dart run studio --theme /path/to/theme --jobs 2
```

- `studio` is a target of `akari run` (`akari run studio --help`).
- Studio always runs in `debug` mode with simulated display data and no backend/D-Bus dependency (`--mode` and `--backend` are not accepted).
- Saving Dart or asset files hot reloads the preview while preserving your current editor document and undo history. Use **Reload from disk** to adopt external file changes.

> [!TIP]
> If shell completion does not list `studio`, refresh your completion scripts with `akari install cli --shell zsh` (or `bash`) and re-source the environment file.

## Editing workflow

1. **Choose a theme and scene**: Select a compiled theme in **Theme** and a scene in **Scenes**, or click **Load JSON** to open any `*.scene.json` file from disk.
2. **Choose components**: Scenes with a declared layout open in **Compose**, where you can toggle optional components and select included components. **Layers** shows compact rows with the layout's component labels, ordered front-to-back, including hidden nodes. **Assets** provides thumbnails and actions for the selected file.
3. **Customize**: The right-hand inspector shows component properties first, followed by position/size and advanced layout controls. Canvas selection automatically reveals the selected row when **Layers** is open.
4. **Apply & preview**: Press `Enter`, leave a field, or click **Apply to preview** to validate and apply edits. Invalid inputs display an error and keep the last valid scene.
5. **Save or undo**: Use **Undo** / **Redo** (`Ctrl+Z` / `Ctrl+Shift+Z`) for history and **Save scene** (`Ctrl+S`) to write changes atomically to the scene JSON.

### Component customization

The **Effects** inspector tab edits background blur and scrim without opening
Settings. Renderers that declare parameters also expose live Shader sliders.
Preset1 includes refraction strength, rain density, flow speed, and dispersion;
use Preview to animate the flow. Slider drags commit one undo step on release,
and saved values run through the same renderer in production.

**Visual style** in the Design inspector provides color pickers, two-color
gradients, borders, corner radius, shadows, backdrop blur, opacity, and typography.
The first edit creates a scene style token; the token selector can reuse an
existing style. Editing a shared token changes every referencing layer.
Sliders preview continuously and commit one history entry on release. These
tokens save in scene JSON and compile into production. Explicit typography needs
component support; Terrace labels and clocks accept the authored text overrides.

Themes can declare editable component properties through their
[`componentCatalog`](../reference/theme-package.md#declaring-editable-component-properties).
Studio shows the author's component and property labels, text inputs, and choice
menus, including defaults for properties absent from the scene JSON.
Viewing a default does not create an edit or add it to the saved scene.

The default theme exposes:

| Component | Controls |
| --- | --- |
| Heading and caption (`terraceLabel`) | **Text**, **Text style: Regular / Large** |
| Date and time (`dateTime`) | **Display: Date / Time** |
| Standby clock (`terraceClock`) | **Clock style: Wide display / Stacked digits / Compact** |

Choices apply immediately; text applies on Enter, blur, or **Apply to preview**.
Both use the existing undo/redo and **Save scene** workflow. Unsupported choices,
including values entered in **Advanced properties**, cannot replace the working
preview or enter history. A choice menu can repair an unsupported JSON draft.

For declared components, additional properties remain available in **Advanced
properties** and are preserved when editing other controls. Components without a
declaration retain their raw string fields. Switching themes also switches their
editing declarations. Hot reload preserves drafts and history; if a changed
declaration invalidates the current scene or history, Studio keeps the previous
theme and reports the refresh error.

### Theme presets

**Compose → Layout preset** switches between Terrace split and Centered column.
Switching restores preset geometry while preserving component properties,
optional omissions, and custom nodes; missing required controls are added in
the same undo step. Newly enabled components use the current layout's positions.

**Compose → Theme presets** displays the theme's declared global choices.
Terrace offers wallpaper-derived, Ocean, Rose, and Violet palettes; airy underline,
frosted capsule, and solid control materials; and Terrace entrance, quiet fade,
and no-animation motion. Changes apply immediately and use scene undo/redo and
save. They are stored in `themeProperties` and resolved by the same theme builder
used in production. **Inspect code** disables these selectors, including keyboard
interaction. Themes may expose presets without declaring layout slots.

### Create an independent theme

Click **Create theme**, enter a lower-case name and a parent folder, then confirm.
Studio copies the current valid design, including pending inspector edits, into a
new theme project and opens its saved composition. You do not need to save over
the source preset first. The new project stays available in **Theme** while Studio
is open. Existing destinations are refused.

The project owns copied scene files, implementation, assets, fonts, shaders, and
licenses. Referenced images from other packages are imported into its assets;
shared SDK path dependencies are rebased. **Assets** lists nested imported files.
To compile the new package identity and reopen it independently, run:

```sh
akari run studio --theme /path/to/new_theme
akari run --theme /path/to/new_theme
akari build --theme /path/to/new_theme
```

**Inspect code** disables creation. Invalid inspector drafts must be corrected
before creating a project.

### Adding and removing layout components

**New scene** creates a separate scene file containing an empty artboard in the
current theme. It refuses existing names and leaves the source scene intact.
**Compose → Component library** adds reusable Text, Rectangle, Circle, and Frame
layers; these work without layout declarations and may be added repeatedly.
Drag horizontally from the library to place a layer at the canvas pointer;
vertical drags scroll the library. Text supports the same inline editing and
style inspector as other text layers. Default create shortcuts are `T`, `U`,
and `F` for text, rectangle, and frame, configurable in Settings.

The left sidebar's **Compose** tab opens by default for scenes with a declared layout.
The default theme's **Terrace** layout offers date, signature, standby clock,
standby greeting, wake hint, sign-in heading, and sign-in caption slots.

- Turn on an optional component to insert a complete node at the theme's preset position, including its
  properties, motion, visibility, and focus settings, then selects it for editing.
- Turn it off to remove it. Turning it on again restores preset defaults;
  use **Undo** to recover the removed node's customizations. Click an added
  component's name to select it in the inspector.
- Each slot can be added once. **Duplicate** and `Ctrl+D` are disabled for layout
  slots; nodes outside the declared layout keep their existing editing behavior.
- **Required controls** lists included controls with a checkmark and missing controls with **Add**.
  Required slots cannot be removed through either the layer actions or canvas
  shortcuts. Terrace requires account selection, session selection, credential
  input, sign-in action, authentication status, and power actions.
- If an imported scene is missing required slots, a notice above all sidebar
  tabs offers **Add required**. This inserts all missing nodes as one undo step.
  An incomplete scene can still be opened and saved while it is being repaired.

All assembly operations validate pending inspector drafts and use the existing
undo/redo and save workflow. **Inspect code** keeps assembly controls read-only.
Insertion defaults survive saved removals and rebuilding. Layout rules apply
only to their declared scene ID; other scenes remain freely editable. Theme
authors can [declare their own slots](../reference/theme-package.md#declaring-layout-slots).

### Responsive layout

The layout inspector supports proportional, fill, and hug width/height modes,
fixed sizes, min/max dimensions, and flex. Hug measures portable text using the
registered font or fits a frame to child bounds, including wrapped lines.
Theme-owned components use explicit/proportional dimensions. Row/column frames
can wrap; fill shares remaining line space within size constraints. Fixed sizes
override proportional/fill dimensions. Interactive minimum hit targets take
precedence over authored maxima.

Choose **Base layout** or add a viewport breakpoint in the inspector. The widest
matching minimum width overrides that node's layout and sizing; removing the
rule restores its base behavior. Rules use the logical viewport supplied to `SceneRuntime`; physical pixel
density does not alter breakpoint matching.

**Width mode** and **Height mode** each use a full-width selector. The **+** and
**−** buttons beside the layout selector add and remove breakpoints. Expand
**Size constraints** for minimum/maximum dimensions and flex; layers with
authored constraints open this section automatically when selected.

**Responsive** below the canvas continuously varies preview width/height without
changing the authored canvas or history. Edit rules in the inspector while
checking the preview. **Authored size** returns to geometry editing.

### Coordinate units

The resolution selector below the canvas applies HD, Full HD, QHD, 4K, portrait,
16:10, and ultrawide reference dimensions immediately, with undo support.
**Compare** displays Full HD, 4K, ultrawide, and portrait outputs together. These
boards retain the same authored reference canvas and vary only output size, just
as production does; entering comparison creates no document edit. **Single**
returns to the original canvas and camera. Settings uses the same preset catalog.

Scene JSON always stores normalized `[0, 1]` coordinates, while the inspector can display reference pixels or percentages. On a `1920x1080` reference canvas, these represent the same rectangle:

| Field | Scene JSON | Reference Pixels | Percentage |
| --- | --- | --- | --- |
| `X` | `0.25` | `480` | `25` |
| `Y` | `0.25` | `270` | `25` |
| `Width` | `0.5` | `960` | `50` |
| `Height` | `0.25` | `270` | `25` |

Transform translations (`translateX`, `translateY`) remain in logical pixels as defined in the [Scene format](../reference/scene-format.md#transforms).

## Canvas tools & gestures

Use the ruler button below the canvas to show rulers and saved reference lines.
Drag from the top ruler to create a vertical guide or from the left ruler for a
horizontal guide. Drag a line to move it; double-click to remove it. Each gesture
is one undo step and guides save with the scene. Smart snapping also targets
visible guides and labels the nearest horizontal/vertical gap in reference pixels.

**State flow** previews Dormant, Login, Submitting, Success, and Error. It also
edits the selected layer's visual transition edges: source condition, target
condition, Shake/Pulse response, and optional duration/delay. The target must be
newly true and the source must match the previous snapshot. Explicit edges take
precedence over simple state-entry responses. **Design → State rules → Edit
compound condition** uses the same nested All/Any/Not composer for visibility.
These rules observe host state; authentication transitions remain backend-owned.

**Timeline** opens scrubbing and play/pause controls for entrance, wake, sleep,
and submit-to-success/error transitions. Each layer has a timing block: drag it
to change delay or its right handle to resize duration and its keyframe span.
Add tracks for opacity, X/Y translation, scale, or rotation; add frames at the
playhead. Drag diamonds to change time; double-click to edit time, value, easing,
or delete a frame. Each drag previews continuously and commits one undo step.
Scrubbing and scenario changes do not enter history. The range starts at 1.5 s
and expands to include authored timing, tracks, and transition responses.

**Advanced layout → Motion** also edits per-node duration, delay, and a custom
Bezier curve. Omitted values inherit theme timing/easing. **Stagger 100 ms** on
multiple selected layers assigns successive delays in paint order as one edit.
The runtime and scrubber use the same evaluator; reduced motion settles tracks
to their final values.

Drag a component row from **Compose** onto the canvas to place it at the pointer.
Dragging an included slot moves that slot without duplicating it. Double-click
a component with a `text` property to edit on the canvas; Enter or clicking
outside commits, and Escape cancels. Smart guides snap moving edges/centers to
visible components and canvas edges/centers with a six-screen-pixel tolerance.
Use the magnet button to toggle guides or hold Alt to bypass them. Grid snapping
takes precedence when enabled. Selection-wide moves retain relative spacing.

Shift-click canvas components or layer rows to toggle multiple selections.
Drag empty canvas space to marquee-select visible layers; Shift adds to the
selection. `Ctrl+A` selects all layers. With sibling layers selected, the
context toolbar offers alignment, equal-gap distribution, and **Group**
(`Ctrl+G`). A group is a real frame; its descendants move, transform, and hide
together. **Frame layout** in the inspector supports absolute, row, and column
placement, padding, gap, alignment, clipping, fixed dimensions, and flex weights.
Nested layer rows show the hierarchy. Pixel geometry uses the parent's content
size. Batch edits, subtree duplication, and deletion each use one undo step;
required layout controls remain protected inside frames. Plain absolute frames
can be ungrouped with `Ctrl+Shift+G` while preserving their children's positions.

Drag a layer row horizontally to reorder it in the hierarchy. Drop near another
row's top/bottom edge to place it before/after that sibling, or in a frame row's
center to nest it. **Move to scene root** removes its parent. Drop indicators
show the insertion edge or destination frame. Moves include the subtree and
use one undo step; cycles are rejected. Reparenting preserves reference geometry
where it fits, bounds it to the destination content, and inherits the new
parent's layout and transforms.

Switch preview states with **State: Login / Dormant**. The adjacent scenario menu
previews password or username input, signing in, rejected credentials,
authentication errors, account/session selection, connecting, and service
unavailability. Choosing a different scenario wakes a dormant preview. These
simulated states never change scene files or undo history; credentials are cleared
on scenario changes.

Click **Preview** to play theme motion and interact with input focus, hover effects,
and choice menus. Use the scenario menu to inspect outcomes. **Edit canvas**
returns to selection and geometry editing; preview input and animation do not
enter document history. Dormant/login switches play the theme's wake transition,
including background blur. Theme and system reduced-motion settings still apply.

Adjust zoom with **− / +**, **100%**, or **Fit**, and select a canvas tool:

| Tool | Shortcut | Behavior |
| --- | --- | --- |
| **Move / Resize** | `V` | Drag to move `x`/`y`, or drag the 8 handles to resize `width`/`height` (hold `Shift` or toggle the lock icon to preserve aspect ratio). |
| **Hand** | `H` / `Space+drag` | Pan the viewport without selecting or modifying nodes. |
| **Scale** | `K` | Drag horizontally/vertically to adjust `scaleX`/`scaleY` (`0.01..100`) around the pivot. Use **Advanced layout -> Reset scale** to reset scale to `1`. |
| **Rotate** | `R` | Drag horizontally to rotate around the Z axis (`rotationZ`). |
| **3D Rotate** | `Shift+R` | Drag horizontally/vertically to adjust `rotationY` and `rotationX`. |

### Additional keyboard shortcuts

**Settings → Shortcuts** lists keyboard commands and mouse gestures. Click a
binding and press a new key combination; Escape cancels recording. Conflicting
combinations name the existing command and must be cleared first. Each command
can be unbound or reset, and **Reset all** restores the defaults. Settings are
saved independently of scenes when applying the dialog. Text fields keep their
own editing keys. Workspace commands such as Save and panel visibility work
from the inspector as well as the canvas.

Mouse settings select middle-button or right-button drag for panning, and the
wheel's zoom modifier (Ctrl, Alt, Super, or none). Holding Space also pans by
default. Navigation does not select or edit layers. Tools live in the canvas's
left rail; state/preview controls are above it, and output size/zoom are below.

| Shortcut | Action |
| --- | --- |
| `Ctrl+Mouse wheel` | Zoom around the pointer |
| `Shift+1` | Fit and recenter the canvas |
| `Arrow` / `Shift+Arrow` | Nudge selected node by `1` / `10` reference pixels |
| `Ctrl+D` | Duplicate a node outside layout slots (`<id>-copy`, `<id>-copy-2`, ...) |
| `Delete` | Delete selected node (disabled for required slots and the last node) |
| `Ctrl+S` | Apply pending inspector fields and save scene JSON |

> [!NOTE]
> Interactive nodes enforce the compiled theme's `minHitTarget` (44 reference pixels in built-in themes), so resize handles cannot shrink an interactive node below that minimum.

## Presets, code inspection, and settings

Workspace controls toggle the sidebar (`Ctrl+B`), inspector (`Ctrl+Shift+B`),
and presentation (`Ctrl+Shift+P`, Escape to exit). Double-click a panel header
to collapse it, or use its float button to detach it inside the workspace.
Floating panels can be moved by their header, resized from the lower-right grip,
and returned with **Dock**. Panel contents, drafts, and selection stay mounted
through these operations. Presentation hides authoring controls, fits the scene,
and restores the editor camera on exit. Smaller windows can reclaim space by
collapsing panels instead of keeping a fixed three-column minimum width.

Panels can dock on either edge, using **Dock left/right** in a floating header
or by dragging the window against an edge. Panels on the same edge become a
tab group; switching tabs retains their fields and scroll state. The workspace
selector offers **Design**, **Motion** (right-side tabs and the timeline), and
**Focus** (hidden side panels). Dock positions, visibility, widths, floating
bounds, and workspace mode restore on the next launch. These are user preferences
and do not create scene history. Collapse and restore controls stay on the
corresponding outer edge, and camera controls occupy a separate footer group.
Canvas shortcuts also work while a layer row is focused; text fields retain
their own editing behavior.

The top bar stays on one row and switches secondary actions to labeled icon
tooltips in narrower windows. New workspaces and workspace presets give the
properties panel 320 pixels; previously saved panel widths are preserved.

- **Presets & projects**: Studio compiles all packages under `themes/` alongside `--theme`. Switching **Theme** (or loading a scene from a registered theme package) switches the component factory, tokens, background renderers, and assets together.
- **Inspect code**: Switch the right panel from **Design** to **Inspect code** to view and copy validated **JSON** or generated **Dart** for the **Selection** or the entire **Scene**.
- **Settings**: The dialog separates **Canvas**, **Background**, **Appearance**, **Grid & snapping**, and **Shortcuts**. Drafts stay intact while switching categories; validation opens the category that needs correction.
  - **Canvas** offers HD, Full HD, QHD, 4K UHD, and portrait presets, custom dimensions, a dimension swap action, `fit`, and `useSafeArea`.
  - **Background** includes an image/color preview, a theme asset chooser, a hexadecimal color field, blur, and scrim opacity.
  - **Appearance** previews Light / Dark / System and the available color palettes. **Grid & snapping** offers common spacing presets and custom `4..512` px spacing. Each editor category can be reset to its defaults.
  - **Apply settings** applies all categories together. Canvas/background changes form one undo step and need **Save scene** to persist. Editor preferences are stored independently when applied; **Cancel** discards the dialog's drafts.

## Importing assets

- **Search & categories**: Filter by path or choose images, SVG icons, fonts, materials/textures, audio, shaders, or other files. Discovery includes declared fonts, shaders, and asset folders outside `assets/`. Selecting a file reveals its preview and actions above the list.
- **Import asset** (in **Assets**): Copies a file into the owning theme's `assets/` directory, registers it in `pubspec.yaml`, and copies its `packages/<theme>/assets/...` path to the clipboard. The imported file becomes selected and clears existing filters.
- **Add to canvas**: Images, textures, and SVGs become independent layers after decoding succeeds. Move, resize, group, style, animate, duplicate, and delete them through the usual canvas tools. The inspector edits fitting and color overrides; SVG color can also be chosen before placement. Layer creation and edits use scene undo/redo and **Save scene**.
- **Use image**: For raster images, validates the file and sets it as the scene background (requires **Save scene** to persist to JSON).
- **Fonts**: The sidebar keeps a one-line sample and single-line filenames. Expand the preview for a larger sample with an adjustable size. **Apply font** saves the font asset on the selection's style token, with undo/redo and independent-theme copying. The typography controls also edit weight, letter spacing, and line height. Font registration is shared between previews and rendering and cached by file revision; previewing alone does not modify the scene.
- **Shader & audio files**: Shaders show a source excerpt; audio files have a dedicated category. Open **Effects → Shader Playground** to edit and compile shader sources. Existing renderer parameter sliders remain available in Effects.
- **Independent themes**: Image/SVG layers retain their fitting and tint when creating a theme. Referenced files from another scene-owning package are copied into the new project.
- **Package resolution**: When opening a scene via **Load JSON**, Studio locates the nearest `theme_*` package boundary to own asset imports. For an unregistered external theme, restart Studio with `--theme /path/to/theme_other` to compile its custom widgets and bundle assets.

## Shader Playground

**Effects → Shader Playground** loads a theme fragment shader or starts with a
working GLSL example. **Compile and preview** invokes the workspace SDK's
`impellerc`, displays diagnostics, and reflects float/vector components and
`sampler2D` slots. Bind floats to constants, time, logical viewport size, pointer
coordinates, Dormant, or Authentication error, with scale and offset. Texture
samplers select theme images. Source edits require recompilation before applying.

**Apply as new shader** preserves the loaded source, creates a new source asset
in its directory, registers `flutter.shaders`, and commits the background reference
and bindings in one undo step. Undo restores the prior background; imported
resources remain available. **Save scene** persists the scene. Independent theme
creation copies/rewrites shader and texture references and registers compilation.
The saved scene uses the same runtime painter, with a stable reduced-motion clock.

Live compilation requires a Flutter SDK (`.fvm/flutter_sdk` in a workspace or
`FLUTTER_ROOT`) and a writable desktop bundle asset cache. Deployed themes consume
Flutter-compiled shaders and do not need Studio or its compiler.

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

The 2026-10-28 workspace regression passed 157 Studio, 42 scene runtime, 37 schema,
6 code generation, and 9 theme synthesis tests. Compatibility checks also passed
15 theme SDK and 42 greeter UI tests. Static analysis and Linux debug builds
passed. An isolated Arch/Sway VM verified native JSON loading and asset
picker display, continuous floating-panel dragging, 150% and 200% scaling on two
outputs, retained panel state after returning from a removed output, the shortcut
settings page, compact font previews, and real shader compile/apply/save.
A separate app depending only on `scene` rendered the saved shader after normal
Flutter shader compilation. VM checks use headless outputs and software graphics;
physical GPU/monitor behavior is outside this run. Local screenshots are under
`build/tool/qa/studio-workspace/`.
