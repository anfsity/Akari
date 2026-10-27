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
- Independent project synthesis and Studio's Create theme flow are implemented
  (`821b045`, `4787227`, `cc65336`). Shared SDK Dart directives and performance
  execution roots are retained when moving a project (`9f303d0`). An external
  synthesized Terrace project passed analysis, all 63 copied theme tests, and
  a release CLI build. Its VM screenshot shows the custom heading, centered
  layout, Violet palette and frosted credential surface.
- Lifecycle previews now cover typed prompt, submitting, rejection, failure,
  account/session choice, connecting and unavailable states while retaining
  preview controllers and keeping document/history untouched.
- Preview mode enables focus, menus and authored motion while isolating canvas
  geometry/keyboard edits. Wake blur uses the production helper, supports reversal,
  and respects theme/system reduced motion. Leaving preview retains borrowed
  controllers and restores selection.
- Terrace now declares wide, stacked and compact standby clock variants through
  the same typed component property used by its renderer. Existing scenes keep
  the original wide clock unless explicitly changed.
- End-to-end native verification is complete. A theme created in the VM from
  pending edits was saved, undone/redone, independently compiled and reopened in
  Studio, then run as a release bundle. Source hashes remained unchanged. Both
  1440×900 and 1280×720 layouts were inspected; preview input retained focus
  without changing the saved document. The full 31-step `akari verify` pipeline
  passed against that external theme, including Studio's 113 tests and the
  private D-Bus smoke check. The current default theme passed all 64 tests.

## Independent project synthesis contract

The export must work for the active edited document, including an imported scene
whose ID differs from the source preset's generated default. It must also work
when the source preset is later removed.

- Shared Flutter-free operations live in `packages/theme_project`. Naming and
  primary-scene discovery have one public entrypoint in `lib/project.dart`;
  source synthesis also parses Dart directives to preserve shared SDK imports.
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
  its manifest. Studio lists nested imported resource paths too.
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

Local review artifacts are in `build/studio-synthesis-review`: `verification.md`
and `verification.json` record native actions, source hashes and screenshots;
`final-verify.json` is the complete passing verification report. Release build
runs are `1793061281448177-43359` (initial external composition) and
`1793062512174284-48066` (project actually created through native Studio).

The isolated release screenshot exercises theme rendering in the unavailable
service state; it does not claim a new real PAM login. The existing login
installation was kept separate from the test desktop.
