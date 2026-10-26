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
- Remaining: richer component variants, faithful file-based
  background previews, runtime state previews, independent project synthesis,
  and end-to-end build/native verification.

Completion requires the entire end state above; a working property editor or
project copy alone is not a completed composition workflow.
