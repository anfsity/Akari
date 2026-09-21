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

The editor starts by opening `lib/themes/default/default.scene.json` from the
repository root. Use the path field and **Open** / **Save** to work on a
different document.

## Features

- Node list in paint order with add, duplicate, and delete.
- Drag to move and drag the corner handle to resize.
- Inspector for rect, transform (including X/Y/Z rotation), layout, and
  properties.
- `visibleWhen` rule builder over the semantic predicate vocabulary.
- Active-predicate toggles to preview conditional nodes.
