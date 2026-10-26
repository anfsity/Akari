# Theme Studio Architecture

Akari combines a compile-time Flutter greeter platform with **Theme Studio**, a live visual editor and diagnostics host. Both consume the same `GreeterHost` contract and `SceneRuntime`. For the wire specification, see the [D-Bus contract](../reference/dbus.md).

## 1. Product shape & end-to-end topology

Akari combines a compile-time Flutter greeter platform with **Theme Studio**, a live visual editor and diagnostics host. Both consume the same `GreeterHost` contract and `SceneRuntime`.

```text
Linux system (greetd / PAM, systemd-logind, desktop session files)
        |
        v
Rust backend bridge (private session bus, AuthActor, io.akari.Greeter1)
        |
        v
Flutter Host Adapter (typed snapshots, prompts, commands, domain streams)
        |
        v
Theme Runtime (host components, custom theme widgets, layout, motion, input)
        |
        v
Theme package (authored with Akari Theme SDK, previewed in Theme Studio)
```

Theme authors own visual presentation (backgrounds, layout, typography, animations, and custom widgets), while Akari supplies four semantic host capabilities:

- **`Password`**: Secure credential input and PAM prompt progression.
- **`Account`**: User selection and avatar/name display.
- **`Session`**: Desktop session selection.
- **`PowerAction`**: Suspend, reboot, and power-off controls.

## 2. Rust backend control plane

| Module | Role |
| --- | --- |
| `backend/src/main.rs` | Service startup, signal handling, and user-side session launcher entrypoints |
| `backend/src/service.rs` | `io.akari.Greeter1` D-Bus server and `systemd-logind` power calls |
| `backend/src/auth.rs` | Single `AuthActor` serializing commands, cancellation, and `attempt_id` ownership |
| `backend/src/greetd.rs` | Framed JSON Unix socket transport (`GREETD_SOCK`) and mock implementation |
| `backend/src/state.rs` | Pure `AuthState` transition machine |
| `backend/src/users.rs` & `session_catalog.rs` | Display-safe user and `.desktop` session discovery |

### Authentication & handoff lifecycle

```text
Idle -> CreatingSession -> PromptPending -> WaitingForInput -> SubmittingResponse
     -> Authenticated -> ResolvingSession -> StartingSession -> HandingOff
```

- Every prompt (`visible`, `secret`, `info`, `error`) is scoped to an `attempt_id`.
- Secret responses stay in zeroizing buffers and never enter logs or D-Bus signals.
- During handoff, Rust validates `session_id`, sends `start_session(cmd, env)` to `greetd`, notifies the UI (`HandingOff`), and closes the greeter so `greetd` can spawn the desktop.

## 3. Flutter host & Theme Runtime

The Flutter host adapter decodes D-Bus signals into independent reactive streams so updates rebuild only the affected UI region:

| Stream / Region | Consumer |
| --- | --- |
| `AuthPrompt` & `Authentication` | Credential field, status messages, and transition state |
| `User` & `Session` catalogs | Account picker and session selector |
| `Power` stream | Power action controls |
| `Theme` & `Studio` overlays | Background renderers, node transforms, selection handles, and guides |

## 4. Theme Studio architecture

| Subsystem | Responsibility |
| --- | --- |
| `ProjectSession` | Scene JSON files, asset imports, atomic save, dirty state, and undo/redo stack |
| `PreviewSession` | Simulated `GreeterHost` states (`Login` / `Dormant`), viewport zoom/pan, and reference resolution |
| `CanvasController` | Node selection, hit testing across 2.5D transforms, and single-commit drag/resize gestures |
| `Inspector` | Validated drafts for layout, transforms, motion presets, and component properties |
| `DiagnosticsPanel` | Schema validation, code inspection (JSON/Dart), and frame budget checks |

Canvas gestures follow a transactional model:
1. **Pointer down**: Capture initial node geometry.
2. **Pointer move**: Update transient preview projection at frame rate without polluting undo history.
3. **Pointer up**: Validate and commit a single undoable edit to the document.

## 5. Verification, performance, and AI tooling

- **Frame budgets**: `16.6 ms` at 60 Hz (`8.3 ms` at 120 Hz), verified across `dormant`, `account selection`, `password prompt`, `authentication error`, `session selection`, and `power menu` states.
- **External AI tool bridge**: Exposes structured project inspection, validation, preview, screenshot comparison, and performance profiling operations (`theme_inspect`, `theme_validate`, `theme_preview`, `theme_screenshot`, `theme_profile`) so AI agents can author and verify themes against the same runtime invariants.
