# Theme Studio

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

1. **Choose a theme and scene**: Select a compiled theme in **THEME** and a scene in **Scenes**, or click **Load JSON** to open any `*.scene.json` file from disk.
2. **Select a node**: Click a node on the canvas or in the **Layers** tab (ordered front-to-back, including nodes hidden in the current preview state). Canvas selection automatically reveals its layer; **Assets** has its own full-height tab with thumbnails and actions for the selected file.
3. **Edit layout & properties**: Update position/size (in reference pixels or percentages), depth (`z`), `renderOrder`, `focusOrder`, transforms, `motion`, or component `properties` in the right-hand inspector.
4. **Apply & preview**: Press `Enter`, leave a field, or click **Apply to preview** to validate and apply edits. Invalid inputs display an error and keep the last valid scene.
5. **Save or undo**: Use **Undo** / **Redo** (`Ctrl+Z` / `Ctrl+Shift+Z`) for history and **Save scene** (`Ctrl+S`) to write changes atomically to the scene JSON.

### Component customization

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

### Coordinate units

Scene JSON always stores normalized `[0, 1]` coordinates, while the inspector can display reference pixels or percentages. On a `1920x1080` reference canvas, these represent the same rectangle:

| Field | Scene JSON | Reference Pixels | Percentage |
| --- | --- | --- | --- |
| `X` | `0.25` | `480` | `25` |
| `Y` | `0.25` | `270` | `25` |
| `Width` | `0.5` | `960` | `50` |
| `Height` | `0.25` | `270` | `25` |

Transform translations (`translateX`, `translateY`) remain in logical pixels as defined in the [Scene format](../reference/scene-format.md#transforms).

## Canvas tools & gestures

Switch preview states with **State: Login / Dormant**, adjust zoom with **− / +**, **100%**, or **Fit**, and select a canvas tool:

| Tool | Shortcut | Behavior |
| --- | --- | --- |
| **Move / Resize** | `V` | Drag to move `x`/`y`, or drag the 8 handles to resize `width`/`height` (hold `Shift` or toggle the lock icon to preserve aspect ratio). |
| **Hand** | `H` / `Space+drag` | Pan the viewport without selecting or modifying nodes. |
| **Scale** | `K` | Drag horizontally/vertically to adjust `scaleX`/`scaleY` (`0.01..100`) around the pivot. Use **Advanced layout -> Reset scale** to reset scale to `1`. |
| **Rotate** | `R` | Drag horizontally to rotate around the Z axis (`rotationZ`). |
| **3D Rotate** | `Shift+R` | Drag horizontally/vertically to adjust `rotationY` and `rotationX`. |

### Additional keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `Ctrl+Mouse wheel` | Zoom around the pointer |
| `Shift+1` | Fit and recenter the canvas |
| `Arrow` / `Shift+Arrow` | Nudge selected node by `1` / `10` reference pixels |
| `Ctrl+D` | Duplicate selected node (`<id>-copy`, `<id>-copy-2`, ...) |
| `Delete` | Delete selected node (disabled when only one node remains) |
| `Ctrl+S` | Apply pending inspector fields and save scene JSON |

> [!NOTE]
> Interactive nodes enforce the compiled theme's `minHitTarget` (44 reference pixels in built-in themes), so resize handles cannot shrink an interactive node below that minimum.

## Presets, code inspection, and settings

- **Presets & projects**: Studio compiles all packages under `themes/` alongside `--theme`. Switching **THEME** (or loading a scene from a registered theme package) switches the component factory, tokens, background renderers, and assets together.
- **Inspect code**: Switch the right panel from **Design** to **Inspect code** to view and copy validated **JSON** or generated **Dart** for the **Selection** or the entire **Scene**.
- **Settings**: The dialog separates **Canvas**, **Background**, **Appearance**, and **Grid & snapping**. Drafts stay intact while switching categories; validation opens the category that needs correction.
  - **Canvas** offers HD, Full HD, QHD, 4K UHD, and portrait presets, custom dimensions, a dimension swap action, `fit`, and `useSafeArea`.
  - **Background** includes an image/color preview, a theme asset chooser, a hexadecimal color field, blur, and scrim opacity.
  - **Appearance** previews Light / Dark / System and the available color palettes. **Grid & snapping** offers common spacing presets and custom `4..512` px spacing. Each editor category can be reset to its defaults.
  - **Apply settings** applies all categories together. Canvas/background changes form one undo step and need **Save scene** to persist. Editor preferences are stored independently when applied; **Cancel** discards the dialog's drafts.

## Importing assets

- **Import asset** (in **Assets**): Copies a file into the owning theme's `assets/` directory, registers it in `pubspec.yaml`, and copies its `packages/<theme>/assets/...` path to the clipboard.
- **Use image**: Select an asset thumbnail, then use the action below the list. Validates that an imported image decodes cleanly and sets it as the scene background (requires **Save scene** to persist to JSON).
- **Package resolution**: When opening a scene via **Load JSON**, Studio locates the nearest `theme_*` package boundary to own asset imports. For an unregistered external theme, restart Studio with `--theme /path/to/theme_other` to compile its custom widgets and bundle assets.

## Troubleshooting

| Symptom | Resolution |
| --- | --- |
| Text looks stretched after resizing | Run **Advanced layout -> Reset scale**, then resize using the **Move** (`V`) handles instead of **Scale** (`K`). |
| Interactive node stops shrinking | It reached the theme's `minHitTarget` (44 px in built-in themes). |
| Canvas drag or command is blocked | Fix the validation error highlighted in the inspector first. |
| External JSON renders with the wrong components | Launch Studio with `--theme /path/to/theme` so its component factory is compiled in. |
| Imported component image does not appear | Background images load directly from disk, but component bundle assets require restarting Studio. |
| Save refuses due to external file modification | Copy any needed values, then click **Reload from disk** before editing again. |

## Verification

`akari verify` runs Studio analysis and tests automatically. To run them directly from `packages/theme_studio`:

```sh
../../.fvm/flutter_sdk/bin/flutter analyze
../../.fvm/flutter_sdk/bin/flutter test
```
