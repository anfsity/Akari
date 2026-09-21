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
packages/mozais_greeter_ui     feature, scene composition, themes  (no dbus)
packages/mozais_scene_editor   desktop editor
<root>  mozais_greeter (app)   main, app wiring, infrastructure/dbus (thin shell)
```

`mozais_greeter_ui` is the planned extraction: the reusable greeter UI, free of
any backend dependency. The app becomes a thin shell that adds the D-Bus
gateway; the editor depends on the library, never on the app. Because Flutter
compiles dependencies into the binary, a distributed editor bundles the real UI
and needs no source tree or app install.

## 3. Implemented

- `visibleWhen` conditions and the presence lifecycle (enter/exit transitions).
- Flutter-free schema package with a JSON codec shared by codegen and tools.
- Editor v0: open/save, paint-order node list, drag-to-move and corner resize,
  inspector (rect, transform including X/Y/Z rotation, layout, properties),
  a flat `visibleWhen` rule builder, and active-predicate toggles.
- Interactive rotation is no longer clamped; `maxInteractiveRotationDegrees`
  was removed from `ThemeTokens`.

## 4. Agreed design

### 4.1 Preview

The preview embeds the real greeter in the editor process:

```text
GreeterFeature(gateway: DemoGreeterGateway())
buildDefaultTheme(document: editedDocument)
GreeterSceneAdapter(feature: ..., theme: ...)
```

- No separate process and no shell scripts; the editor owns everything.
- Scene edits render live (in-memory `SceneDocument`, no codegen).
- Widget-code edits update through the editor's own `flutter run` hot reload.
- An **Outline / Real** toggle keeps the placeholder preview for layout work.
- Requires `buildDefaultTheme({Color? seed, SceneDocument? document})` as the
  document-injection seam, and an editor-side background renderer that loads
  `assets/...` from the repository root.

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
- Inspector sliders and numeric fields remain for precise values.

### 4.3 Settings

A settings route with grouped options:

- **Appearance**: editor theme, language.
- **Editing**: confirm unsaved changes, grid snap, preview aspect ratio.
- **Files**: default scene path.

Editor themes are well-known palettes mapped to a `ColorScheme`: Catppuccin
(Latte/Mocha), Tokyo Night, GitHub (Light/Dark), Nord, Dracula. They affect the
editor UI only, never the greeter's compile-time `ThemeTokens`. Settings persist
to `~/.config/mozais/scene_editor.json` with `dart:io`. The settings page shows
a live preview of the selected theme.

Language is English only for now, behind an `EditorStrings` abstraction with an
`EnglishStrings` implementation and a locale registry, so adding a locale is a
drop-in. No ARB or `flutter_localizations`.

### 4.4 Unsaved changes

When the document is dirty, Open, window close, and switching documents prompt
**Save / Discard / Cancel**. The prompt is controlled by `confirmUnsavedChanges`
(default on). Window close is intercepted with `AppLifecycleListener.onExitRequested`.

### 4.5 Layout

- Draggable dividers between panes, with a `resizeLeftRight` cursor and
  min/max widths.
- The right sidebar defaults narrower, is resizable, and groups the inspector
  into tabs (Identity / Layout / Transform / Visibility / Properties) so it is
  not a crowded wall of controls.

### 4.6 Document panel and background import

- A Document panel edits `canvas` and `background`, which the inspector does not
  currently expose.
- Import picks a file, copies it into the asset directory, and sets
  `background.kind` + `asset`.
- `SceneBackgroundKind.video` has no renderer yet, so a video import would fall
  back to solid until a `video_player`-based renderer exists.

### 4.7 Visibility UI

- Human labels for the predicate vocabulary (`isDormant` → "asleep", etc.).
- Presets such as asleep / awake / authenticating / error / user selected.
- Keep the ALL/ANY rule builder, with labels, for fine control.
- Nested conditions move under **Advanced**.
- Live in the tabbed inspector to avoid crowding.

## 5. Roadmap

1. **Quick wins**: draggable dividers, unsaved-change prompt, settings page with
   named themes, language seam, and persistence.
2. **Mouse rework**: public transform matrix, transform-following selection box,
   Z rotation dot, trackball sphere.
3. **Real preview**: extract `mozais_greeter_ui`, add the document-injection
   seam, embed the greeter, add the Outline/Real toggle.
4. **Document panel and background import**.
5. **Visibility UI rework**: labels, presets, Advanced, inspector tabs.

## 6. Deferred

- Trackball: orbit first, arcball only if needed.
- Video background renderer.
- Grid-snap behavior details.
- A better right-sidebar arrangement if one emerges.
- Languages beyond English.
