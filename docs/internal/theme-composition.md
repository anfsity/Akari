# Theme composition implementation

The target is a complete preset authoring and theme synthesis workflow. Theme
authors own the available designs and compatibility rules; Studio presents and
combines those designs. Code-owned widgets and shaders remain supported.

## Required end state

- Persist theme-level selections in scene JSON and generated Dart.
- Resolve the authored scene through the same theme builder in Studio and the
  production host, including imported wallpaper and extracted palette seeds.
- Offer real layout, component style, palette, material, and motion choices.
  Layout changes preserve customized content and place components coherently.
  Incompatible choices are rejected before preview, history, or saving.
- Preview the login lifecycle, including dormant, input, submitting, and error
  states, without exposing authentication implementation to the author.
- Create an independent theme from a compiled preset. Preserve edited scenes,
  code, asset and font references, package identity, and build entrypoints.
  Never overwrite the source preset or an existing destination.
- Reopen, build, and run the synthesized theme with the same appearance.
- Verify undo/redo, save/reopen, code generation, build, and native UI behavior
  in the provided virtual machine at normal and compact window sizes.

## Decisions and progress

- Scene `themeProperties` stores theme-owned string choices. The scene codec
  checks the data shape; theme declarations validate supported values. Omitted
  choices retain author defaults without rewriting the document. JSON and Dart
  round trips are covered by tests (commit `c0fb434`).
- Builders now receive the editing document (`d30c313`). A typed preset catalog
  is shared with runtime (`00c23f5`); no-motion policy reaches scene widgets and
  wake transitions (`1aeb860`). Terrace implements palette, material, and motion
  presets, including 36 tested combinations (`93709c7`). Studio controls use
  document validation, history, saving, and read-only inspection.
- Terrace split and centered layouts now compose all 72 global preset
  combinations. Layout changes preserve edited content, optional omissions and
  custom nodes, repair required controls, and update insertion defaults.
- File-based previews now bind images through the theme's own background
  renderer, preserving its gradients, focal alignment, and custom atmosphere.
  Themes without an image renderer no longer offer wallpaper replacement.
- Remaining: richer component variants, runtime state previews, independent
  project synthesis, and end-to-end build/native verification.

## Next implementation: independent project synthesis

The export must work for the active edited document, including an imported scene
whose ID differs from the source preset's generated default. It must also work
when the source preset is later removed.

- Introduce shared Flutter-free project operations for Studio and the CLI.
  Package/builder naming is currently private in `tool/src/theme/project.dart`;
  keep that business rule authoritative when Studio creates new package names.
- Copy the source's own code and declared resources, preserving licenses and
  shaders. Exclude build caches and generated scene files. Rebase local SDK and
  development dependency paths from the source to the destination project.
- Retain the source factory under a local library name and generate the new
  public builder entrypoint. It delegates to the copied local implementation
  with the active composition document, then assigns the new theme identity.
  It must never depend on another concrete theme package.
- Save the edited document to a dedicated composition scene and generate its
  Dart before opening the result. Share the generator's document-getter naming
  rule rather than duplicating it. Preserve scene IDs for layout declarations.
- Define an explicit primary scene in project metadata (for example
  `akari.scene`) so Studio and CLI reopening select the composition rather than
  whichever source scene happens to sort first.
- Rewrite self-package asset/font/library references to the new namespace.
  Copy imported external resources into the new package and register them in
  its manifest. Studio's current asset list is shallow and must list nested
  imported resource paths too.
- Stage the complete project before publishing it. Refuse existing targets and
  source/destination nesting; failures must leave the source and target intact.
- Add a Create theme flow for name and destination. It exports pending valid
  edits without first saving over the source preset, opens the independent
  project, and retains it in the running Studio's project selector.
- Until recompilation, Studio can use the already-compiled source factory with
  the new document and file-backed resources. Reopening through the CLI must
  compile the copied source under the new package identity and resolve its own
  fonts, assets, scene and entrypoint.

Tests must cover source preservation, naming, path rebasing, resource/namespace
rewriting, edited-document restoration, failed/existing destinations, UI
creation and switching, and an actual build and VM run of the created project.

Completion requires the entire end state above; a working property editor or
project copy alone is not a completed composition workflow.
