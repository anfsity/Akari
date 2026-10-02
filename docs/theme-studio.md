# Theme Studio

Theme Studio is the Linux scene editor for a compiled Mozais theme. Its editor
controls use `shadcn_flutter`; the preview renders the selected theme's own
components, tokens and assets through `SceneRuntime`.

```sh
mozais run studio --theme themes/default
# Without the installed launcher:
fvm dart run tool/mozais.dart run studio --theme themes/default
# External theme packages work the same way.
fvm dart run tool/mozais.dart run studio --theme /path/to/theme --jobs 2
```

`studio` is a `run` target. `mozais run --help` lists it, and
`mozais run studio --help` shows its options. If an existing shell does not
complete it, refresh the installed scripts with `mozais install --shell zsh`, then run
`. ~/.local/share/mozais/env.zsh` in that shell. For bash, use `--shell bash`
and source `~/.local/share/mozais/env.bash` instead.

The CLI resolves the theme, generates its scene Dart, and creates a reusable
host in `build/tool/hosts/<encoded-canonical-theme-path>/studio/`. The editor
uses simulated display data and has no backend or D-Bus dependency. Production
hosts do not depend on the editor or its UI library. `--dry-run` prints the plan;
`--format json` and `--report PATH` use the normal tooling report protocol.
Studio runs in debug mode. Dart and asset edits use the existing hot reload
session; saving scene JSON also regenerates the compiled scene. Hot reload
keeps the editor's current document and undo history. Use **Reload from disk**
to explicitly adopt changes made by another editor.

## Editing a scene

1. Select a scene from the left panel. Save or discard changes before switching.
2. Select a node on the canvas or in the layer list. The list also includes
   nodes hidden by the current preview state, ordered from front to back.
3. Edit normalized position/size, depth, paint/focus order, transforms, motion,
   or the component's string-valued JSON properties in the inspector.
4. Click **Apply to preview**, or press Enter in a numeric field. Invalid edits
   show an error and retain the last valid document. Selecting another node
   applies valid pending fields first.
5. Use **Undo** and **Redo** for document edits. **Save scene** applies pending
   fields and writes the scene JSON. **Reload from disk** requires an explicit
   discard action and clears history.

Use **Duplicate node** in the layer panel to copy the selected node, including
its layout, transforms, visibility, motion and properties. The copy is selected
and receives a unique ID (`<id>-copy`, then `<id>-copy-2`, and so on). It starts
at the same position; edit its layout in the inspector to move it.
**Delete node** removes the selected node and selects a neighboring node in
authoring order. A scene must retain at least one node, so deletion is disabled
for the last node. Both actions apply valid inspector drafts first and stop on
invalid fields. They support undo/redo, including restoration of selection;
undoing a deletion restores the node with its applied draft edits. Changes
reach disk only when explicitly saved.

Preview renders at the scene's reference resolution and scales to fit the
workspace. **State: Login / Dormant** switches between two simulated display
states. Component interactions are intercepted for selection. Node hit testing
uses the runtime's transforms and visibility rules. Animations are disabled in
the editing canvas so selection and property inspection remain stable.

The codec used by code generation also validates edited documents. Saving
writes a sibling temporary file and renames it over the authoring file only
after a complete write. It refuses to save when the source changed externally,
leaving both the external file and the editor's unsaved document available.

New nodes can currently be created by duplication. Adding an arbitrary
component, dragging or resizing on the canvas, editing visibility rules and
backgrounds, additional preview states, and unsaved-work recovery after closing
the application are not implemented. Save explicitly before closing the window.
Custom property names and values remain the responsibility of the compiled
component.

## Checks

`mozais verify` includes Studio dependency resolution, analysis and tests.
Focused checks can be run from `packages/theme_studio`:

```sh
../../.fvm/flutter_sdk/bin/flutter analyze
../../.fvm/flutter_sdk/bin/flutter test
```
