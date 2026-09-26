# Mozais Scene Editor

Design and roadmap for the desktop tool that authors `.scene.json` documents.
The runtime contract itself is in `docs/frontend-architecture.md`; this file
covers the editor's architecture, agreed interaction design, and planned work.

## 1. Purpose

The editor is a first-class, distributable tool, not an internal-only script.
It edits the same model the runtime consumes and previews the **real greeter
UI**, so theme authors can iterate without running the login stack.

## 2. Package layout

```text
packages/mozais_scene_schema   Flutter-free model, condition evaluator, JSON codec
packages/mozais_scene          runtime, theme bundle, background and motion registries
packages/mozais_scene_codegen  build_runner generator (decode JSON, emit Dart)
packages/mozais_greeter_ui     feature and scene composition (no dbus)
packages/mozais_theme_sdk      semantic Host API for compiled themes
packages/mozais_theme_default  built-in default theme
packages/mozais_theme_fallback built-in fallback theme
packages/mozais_theme_catalog  compile-time selection of built-in themes
packages/mozais_scene_editor   desktop editor
<root>  mozais_greeter (app)   main, app wiring, infrastructure/dbus (thin shell)
```

`mozais_greeter_ui` is the reusable greeter UI, free of any backend
dependency. The app is a thin shell that adds the D-Bus gateway; the editor
depends on the library, never on the app. Because Flutter compiles dependencies
into the binary, a distributed editor bundles the real UI and needs no source
tree or app install.

## 3. Implemented

- `visibleWhen` conditions and the presence lifecycle (enter/exit transitions).
- Flutter-free schema package with a JSON codec shared by codegen and tools.
- Editor v0: open/save, paint-order node list, drag-to-move and corner resize,
  inspector (rect, transform including X/Y/Z rotation, layout, properties),
  a flat `visibleWhen` rule builder, and active-predicate toggles.
- Interactive rotation is no longer clamped; `maxInteractiveRotationDegrees`
  was removed from `ThemeTokens`.
- Localized UI copy behind `EditorStrings`, with `EnglishStrings` and a locale
  registry; transient status messages are structured, not baked strings.
- Settings page: named editor themes, language, unsaved-change confirmation,
  grid-snap and preview-aspect-ratio options, and a default scene path. The
  page persists to `~/.config/mozais/scene_editor.json`. A light/dark toggle
  in the app bar switches a theme to its partner in the opposite brightness.
  Grid-snap behavior itself is still deferred.
- Draggable pane dividers with min/max widths and a `resizeLeftRight` cursor;
  the line thickens on hover and the right sidebar can be collapsed to a rail.
- Unsaved-change prompt on Open and window close, controlled by
  `confirmUnsavedChanges` and using `AppLifecycleListener.onExitRequested`.
- The selection overlay follows the node's transform through the shared
  `sceneNodeRect` and `sceneNodeTransformMatrix` helpers: a dashed box with a
  corner resize handle, a dot above the box for in-plane rotation, and a
  translucent trackball for X/Y rotation. The cursor changes per region. The
  overlay is hidden while the node is not visible under the active predicates,
  so a gated node cannot leave a phantom box over the scene.
- Clicking a node in the preview selects the topmost visible node under the
  pointer. The embedded scene is cached so moving the selection does not
  rebuild the background, blur, or greeter widgets.
- The reusable UI is extracted into `mozais_greeter_ui`; the app is a thin
  shell over it. The editor previews the edited document with the real theme.
  The editor embeds
  `GreeterFeature(DemoGreeterGateway())` and `GreeterSceneAdapter` behind an
  **Outline / Real** toggle, and resolves background assets from the repository
  root with a file-based image provider.
- The inspector is tabbed (Document / Identity / Layout / Transform /
  Visibility / Properties); its tab strip scrolls with the wheel or a
  middle-button drag. The Document tab edits `canvas` and `background`;
  background import copies a file into the repository `assets/` directory and
  picks `image` or `video` from the extension. A video background renders solid
  until a video renderer exists.
- Scenes open through the same file picker as background import. The picker's
  address bar accepts a typed folder or file path and can filter the listing by
  extension.
- The Visibility tab uses human-labeled predicates, common presets, the
  ALL/ANY rule builder, and an Advanced view for nested conditions. The
  sidebar's active-predicate toggles share the same labels.

## 4. Agreed design

### 4.1 Preview

The preview embeds the real greeter in the editor process:

```text
GreeterFeature(gateway: DemoGreeterGateway())
ThemeRegistry.resolve('default').copyWith(document: editedDocument)
GreeterSceneAdapter(feature: ..., theme: ...)
```

- No separate process and no shell scripts; the editor owns everything.
- Scene edits render live (in-memory `SceneDocument`, no codegen).
- Widget-code edits update through the editor's own `flutter run` hot reload.
- An **Outline / Real** toggle keeps the placeholder preview for layout work.
- Theme packages own their scenes, component assemblies, tokens, and assets.
  The editor resolves the same compile-time catalog as the greeter and loads
  both repository `assets/...` and theme package assets from the checkout.

### 4.2 Mouse manipulation

- A dashed selection box, slightly larger than the node, follows the node's
  transform so it rotates with the node. This needs a public transform-matrix
  helper shared by the runtime and the overlay (including the inverse).
- Inside drag moves; the corner handle resizes.
- A dot above the box rotates in plane (`rotationZ`).
- A translucent **trackball sphere** rotates in 3D (`rotationX` / `rotationY`).
  Start with orbit mapping (drag delta to rotation); upgrade to a true arcball
  if the feel is not good enough.
- The cursor changes per region (move / rotate / resize).
- The overlay covers the whole preview and translates pointer positions into
  canvas space, so a handle that falls outside the canvas stays grabbable.
- An **Interact** toggle removes the overlay so the embedded greeter receives
  pointer events directly for a full interactive preview.
- Inspector sliders and numeric fields remain for precise values.

### 4.3 Settings

A settings route with grouped options:

- **Appearance**: editor theme, language.
- **Editing**: confirm unsaved changes, grid snap, preview aspect ratio.
- **Files**: default scene path.

Editor themes are well-known palettes mapped to a `ColorScheme`: Mozais Aurora
(Aurora/Aurora Dawn), Catppuccin (Latte/Mocha), Tokyo Night, GitHub
(Light/Dark), Nord, and Dracula. They affect the editor UI only, never the
greeter's compile-time `ThemeTokens`. Settings persist to
`~/.config/mozais/scene_editor.json` with `dart:io`. The app restyles
immediately, so the page has no separate preview card; a light/dark toggle in
the app bar switches to the opposite brightness of the current theme. The
editor also provides Ctrl/Cmd+S, Ctrl/Cmd+O, and Delete shortcuts for the
common document and node actions.

Language is English only for now, behind an `EditorStrings` abstraction with an
`EnglishStrings` implementation and a locale registry, so adding a locale is a
drop-in. No ARB or `flutter_localizations`.

### 4.4 Unsaved changes

When the document is dirty, Open, window close, and switching documents prompt
**Save / Discard / Cancel**. The prompt is controlled by `confirmUnsavedChanges`
(default on). Window close is intercepted with `AppLifecycleListener.onExitRequested`.

### 4.5 Layout

- Draggable dividers between panes, with a `resizeLeftRight` cursor and
  min/max widths. The line thickens on hover so it is easy to find.
- The right sidebar defaults narrower, is resizable, collapses to a rail, and
  groups the inspector into tabs (Identity / Layout / Transform / Visibility /
  Properties) so it is not a crowded wall of controls. The tab strip scrolls
  with the wheel or a middle-button drag.

### 4.6 Document panel and background import

- A Document panel edits `canvas` and `background`, which the inspector does not
  currently expose. The background asset is a read-only path field with an
  import button; color, scrim, and blur live in a separate Backdrop card. The
  color field opens a palette picker with a curated swatch grid and a hex
  field.
- Import picks a file, copies it into the asset directory, and sets
  `background.kind` + `asset`.
- The same picker opens scene documents: its address bar accepts a typed folder
  or file path, and an extension filter narrows the listing.
- `SceneBackgroundKind.video` has no renderer yet, so a video import would fall
  back to solid until a `video_player`-based renderer exists.

### 4.7 Visibility UI

- Human labels for the predicate vocabulary (`isDormant` → "asleep", etc.).
- Presets such as asleep / awake / authenticating / error / user selected.
- Keep the ALL/ANY rule builder, with labels, for fine control.
- Nested conditions move under **Advanced**.
- Live in the tabbed inspector to avoid crowding.

## 5. Roadmap

All planned batches are implemented. Remaining work is listed under Deferred.

## 6. Deferred

- Trackball: orbit first, arcball only if needed.
- Video background renderer.
- Grid-snap behavior details.
- Languages beyond English.
