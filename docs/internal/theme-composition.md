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
- Next: make theme builders consume the editing document, then implement the
  theme preset catalog and its Studio controls. Follow with layout composition,
  runtime state previews, and independent project synthesis.

Completion requires the entire end state above; a working property editor or
project copy alone is not a completed composition workflow.
