# Theme Studio Architecture

Akari pairs a compile-time Flutter greeter platform with **Theme Studio**, a visual scene editor and preview host. Both runtimes consume the same `GreeterHost` contract and `SceneRuntime`. For the backend IPC specification, see the [D-Bus contract](../reference/dbus.md).

## 1. Product shape & end-to-end topology

```text
Linux system (greetd / PAM, systemd-logind, desktop session files)
        |
        v
Rust backend bridge (private session bus, AuthActor, io.akari.Greeter1)
        |
        v
GreeterFeature & GreeterSceneAdapter (state machine, ScenePredicate flags, GreeterHost slots)
        |
        v
SceneRuntime & ThemeBundle (normalized layout, frames, style tokens, shaders, motion)
        |
        v
Theme package (authored with Akari Theme SDK, edited and previewed in Theme Studio)
```

Theme authors own visual presentation—backgrounds, shaders, layout, typography, animations, and custom widgets—while Akari provides semantic host state and callbacks:

- **Account selection**: Available users, selected user identity, and `onSelectUser`.
- **Session selection**: Validated `.desktop` sessions, active selection, and `onSelectSession`.
- **Credential prompts**: Borrowed credential text/focus controllers, prompt kind/status, `onRespondToPrompt`, and `onStartSession`.
- **Power actions**: Suspend, reboot, and power-off controls via `onRequestPowerAction`.

## 2. Rust backend control plane

| Module | Role |
| --- | --- |
| `crates/akari-backend/src/main.rs` | Mode dispatch (D-Bus daemon vs. user-side session launcher) and signal handling |
| `crates/akari-backend/src/service.rs` | `io.akari.Greeter1` D-Bus interface and `systemd-logind` power calls |
| `crates/akari-backend/src/auth/` | `AuthHandle`, single-queue `AuthActor`, active `Attempt` lifecycle, and caller disconnect watch |
| `crates/akari-backend/src/greetd/` | Wire protocol frames (`protocol.rs`), Unix socket transport (`transport.rs`), and mock transport (`mock.rs`) |
| `crates/akari-backend/src/state.rs` | Pure `AuthState` transition state machine |
| `crates/akari-backend/src/users.rs` & `session_catalog.rs` | Interactive account discovery and `.desktop` session validation |
| `crates/akari-backend/src/session_launch.rs` | Two-stage user login-shell forwarding (`--start-session` / `--exec-desktop`) |

### Authentication & handoff lifecycle

```text
Idle -> CreatingSession -> PromptPending -> WaitingForInput -> SubmittingResponse
     -> Authenticated -> ResolvingSession -> StartingSession -> HandingOff
```

- Every prompt (`visible`, `secret`, `info`, `error`) is scoped to a unique `attempt_id`.
- Secret responses use zeroizing buffers and are never written to logs or D-Bus signals.
- During handoff, Rust validates `session_id`, sends `start_session(cmd, env)` to `greetd`, emits `StateChanged("HandingOff")`, and exits the greeter so `greetd` can launch the desktop.

## 3. Flutter host & scene runtime

`GreeterSceneAdapter` projects `GreeterState` into `ScenePredicate` flags and narrow `ValueListenable` slots on `GreeterHost`, ensuring state updates rebuild only subscribed widgets:

| Slot / Projection | Consumer |
| --- | --- |
| `userSlots` (`ValueListenable<UserSlots>`) | Account picker and avatar/display name widgets |
| `sessionSlots` (`ValueListenable<SessionSlots>`) | Desktop session selector |
| `promptSlots` (`ValueListenable<PromptSlots>`) | Credential input field, prompt label, and submit action |
| `powerSlots` (`ValueListenable<PowerSlots>`) | Power action controls |
| `serviceSlots` (`ValueListenable<ServiceSlots>`) | Service status indicators and error banners |
| `activePredicates` (`Set<ScenePredicate>`) | Per-node `visibleWhen` evaluation, state effects, and transition edges |

## 4. Theme Studio architecture

Theme Studio (`packages/theme_studio/`) is organized into focused internal domains backed by pure Dart project synthesis in `packages/theme_project/`:

| Domain | Key owners & responsibilities |
| --- | --- |
| `authoring/` | `SceneEditor` (active `SceneDocument`, selection, undo/redo history, atomic save), component assembly (`ThemeLayoutDefinition`), and independent theme synthesis (`StudioCreateTheme`) |
| `canvas/` | `StudioViewport` (pan/zoom camera), `node_geometry.dart` (2.5D hit testing and resize/rotate math), `smart_guides.dart`, rulers, and multi-resolution comparison boards |
| `inspector/` | `NodeInspectorController` (validated field drafts), component/preset property controls, frame/responsive breakpoint editors, style token editors, and `CodeInspector` (JSON/Dart preview) |
| `preview/` | `StudioPreviewHost` (simulated `GreeterHost` scenarios such as dormant, prompting, submitting, auth error, and service unavailable without a backend daemon) |
| `resources/` | `StudioAssets` (asset discovery, package import, image/SVG canvas layers, font registration) and `StudioShaderCompiler` / `StudioShaderPlayground` (live `impellerc` reflection and binding) |
| `timeline/` | `StudioTimeline` (deterministic scrubbing, duration/delay blocks, keyframe property tracks) and `StudioStateGraph` (visual transition edge authoring) |
| `workspace/` | `StudioWorkspaceLayout` (dockable/floating panels, `Design`/`Motion`/`Focus` modes), customizable keyboard/mouse shortcuts, and persistent editor preferences |

Canvas and slider gestures follow a single-commit transactional model:
1. **Interaction start**: Capture initial node geometry or property state.
2. **Drag / scrub**: Update the live preview at frame rate without pushing intermediate undo entries.
3. **Interaction end**: Validate and commit a single undoable edit to `SceneEditor`.

## 5. Verification & performance

- **Repository verification (`akari verify`)**: Runs static analysis, Rust unit/integration tests, scene schema/codegen checks, and widget/editor test suites across all shared packages and themes.
- **Performance harness (`packages/greeter_harness/`)**: Shares automated preview journeys (`face-success`, `password-fallback`), frame attribution, and timeline aggregation across `akari preview`, `akari verify-perf`, and `akari trace-perf`.
