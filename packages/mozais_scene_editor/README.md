# Mozais Scene Editor

A desktop tool for authoring `.scene.json` documents used by the Mozais
greeter. It edits the same model the runtime consumes: the preview is the real
`SceneRuntime`, so layout, transforms, motion, and `visibleWhen` conditions
render exactly as they will at login.

## Running

```sh
cd packages/mozais_scene_editor
fvm flutter run -d linux
```

The editor starts by opening the configured default scene path, or
`packages/mozais_greeter_ui/lib/themes/default/default.scene.json` from the
repository root when none is set. **Open** picks a `.scene.json` file through
the built-in file browser; the path field still accepts a path directly.

## Features

- Node list in paint order with add, duplicate, and delete. Clicking a node in
  the preview selects the topmost visible node under the pointer.
- Drag inside the selection box to move; drag the corner handle to resize.
- A dashed selection box follows the node's transform (including rotation and
  perspective), with a dot for in-plane rotation and a trackball for X/Y
  rotation. The cursor changes per region, and the box is hidden while the node
  is not visible under the active predicates. Handles outside the canvas stay
  grabbable.
- **Interact** toggle removes the selection overlay so the embedded greeter is
  fully usable; **Edit** restores selection and drag.
- Tabbed inspector (Document / Identity / Layout / Transform / Visibility /
  Properties) for the document, rect, transform (including X/Y/Z rotation),
  layout, and properties. The tab strip scrolls with the wheel or a
  middle-button drag.
- A Document tab edits `canvas` and `background`. Import copies a file into the
  repository `assets/` directory and sets the background kind from the
  extension; a video import renders solid until a video renderer exists. The
  picker's address bar accepts a typed folder or file path, and the color field
  opens a palette picker.
- `visibleWhen` builder with human-labeled predicates, common presets
  (asleep / awake / authenticating / error / user selected), the ALL/ANY rule
  builder, and an Advanced view for nested conditions.
- Active-predicate toggles, using the same labels, to preview conditional
  nodes.
- Draggable pane dividers with min/max widths and a hover highlight. The
  inspector collapses to a rail from the app bar.
- **Outline / Real** preview toggle. Real embeds the actual greeter widgets and
  theme, rendering the edited document live; background assets are read from the
  repository root.
- Settings page with named editor themes, a language seam, unsaved-change
  confirmation, grid-snap and preview-aspect-ratio options, and a default scene
  path. Settings persist to `~/.config/mozais/scene_editor.json`. An app-bar
  toggle switches the current theme to its light or dark counterpart.
- Save / Discard / Cancel prompt when opening a document or closing the window
  with unsaved changes.
