# Mozais Frontend Architecture

## 1. Purpose and Scope

This document defines the architecture of the Mozais greeter frontend. It
describes how the Flutter application turns backend events and user intents
into a layered visual experience without coupling authentication code to
layout or rendering code.

The document covers:

1. The boundary between the Flutter frontend and the Rust backend.
2. The four frontend layers: Feature, Scene, Visual, and Theme.
3. The relationship between backend state, presentation state, and local UI
   interaction state.
4. The typed `GreeterSceneSlots` contract between Feature and Scene.
5. Scene orchestration, Visual lifecycle, Theme tokens, security, testing, and
   implementation order.

This document does not replace [the D-Bus contract](dbus-contract.md). The
D-Bus contract remains the authority for wire signatures, attempt IDs,
authentication protocol states, session validation, and secret-handling rules.

## 2. Architectural Decision

The proposed four-layer model is accepted as the internal architecture of the
Flutter frontend:

```text
User input / platform events
              |
              v
      +-------------------+
      | Feature           |
      | Use cases, intent,|
      | state projection, |
      | D-Bus client port |
      +---------+---------+
                |
                | typed GreeterSceneSlots
                v
      +-------------------+
      | Scene             |
      | Layout, stack,    |
      | transition,       |
      | coordination      |
      +---------+---------+
                |
                | VisualContext / layer commands
                v
      +-------------------+
      | Visual            |
      | Live2D, shader,   |
      | video, particles, |
      | static fallback   |
      +-------------------+

      +-------------------+
      | Theme             |
      | Color, typography,|
      | spacing, shape,   |
      | blur, motion      |
      +-------------------+
         consumed by Scene and Visual
```

The four layers are not a replacement for the system-level backend boundary.
The complete runtime remains:

```text
Flutter Feature
    |
    | private/session D-Bus
    v
Rust backend bridge
    |                         \
    | greetd Unix socket       \ system D-Bus
    v                           v
greetd / PAM                systemd-logind
```

The Rust backend owns privileged or security-sensitive system integration. The
Flutter application owns presentation and user interaction. Neither side may
silently absorb the responsibilities of the other.

## 3. Existing Runtime Boundary

The backend already provides the security and concurrency boundary required by
the frontend:

- `AuthActor` serializes authentication commands and owns the active greetd
  transaction.
- `AuthStateMachine` validates authentication transitions independently from
  D-Bus and socket I/O.
- `attempt_id` prevents stale UI responses from reaching an older transaction.
- `GreeterService` exposes the D-Bus interface to the Flutter client.
- Session commands are resolved and validated by the backend; the UI does not
  send arbitrary `Exec` strings.
- Power requests are routed through the backend to systemd-logind.

The frontend must consume this boundary rather than reimplement it. In
particular, the Flutter Feature layer must not open the greetd socket, parse
PAM frames, call systemd-logind directly, or infer that a session is executable
from display metadata.

The current D-Bus service coordinates are:

```text
Bus name:    io.mozais.Greeter
Object path: /io/mozais/Greeter
Interface:   io.mozais.Greeter1
```

The current backend authentication state is intentionally more detailed than
the visual state. It includes phases such as `CreatingSession`,
`PromptPending`, `WaitingForInput`, `SubmittingResponse`, `Authenticated`,
`ResolvingSession`, `StartingSession`, `HandingOff`, `Cancelling`, and
`Failed`. The frontend may project these values into a smaller semantic model,
but must not remove information needed to handle stale attempts, repeated PAM
prompts, cancellation, or session handoff.

## 4. Layer Responsibilities

### 4.1 Feature: Business Use Cases and Presentation State

Feature is the application-facing layer. It understands user intent and the
semantic meaning of backend results, but it does not render pixels.

Feature responsibilities:

- Load users and the session catalog independently before authentication.
- Track the selected user and selected desktop session.
- Start, respond to, cancel, and restart authentication attempts.
- Track the current `attempt_id` and reject stale local events.
- Convert D-Bus replies and signals into typed frontend state.
- Expose display-safe errors and prompt information.
- Request power operations through the backend client.
- Decide which commands are enabled in the current state.
- Produce an immutable `GreeterSceneSlots` snapshot and typed region slots for
  Scene.
- Emit one-shot effects such as focus requests, notification requests, or
  application exit after successful session handoff.

Feature must not:

- Know widget tree structure, pixel positions, z-order, or animation curves.
- Choose whether the background is Live2D, video, shader, or static artwork.
- Call `setState` from domain or transport code.
- Expose a generic map of backend fields to the Scene.
- Put plaintext passwords into persistent application state or scene slots.
- Treat visual editing state as a backend authentication state.

Feature should depend on ports rather than concrete D-Bus implementation
classes:

```text
Feature use cases
    |
    +-- GreeterGateway       -> authentication, users, sessions
    +-- PowerGateway         -> power actions
    +-- ClockGateway         -> current time, if needed by presentation
    +-- PreferencesGateway   -> local visual preferences, if needed
```

The concrete D-Bus client belongs below these ports. This keeps Feature tests
deterministic and allows the Scene to be tested without a running bus.

### 4.2 Scene: Spatial Composition and Transition Orchestration

Scene is the director of the current visual composition. It receives semantic
slots and turns them into a stable layout and a set of visual layers.

Scene responsibilities:

- Define the spatial layout of the greeter.
- Manage the visual stack and its ownership order.
- Coordinate background, foreground, overlays, dialogs, and system controls.
- Apply responsive constraints for desktop, small screens, and unusual aspect
  ratios.
- Compose trusted static image layers and 2.5D planes without owning
  authentication state.
- Decide how a semantic state change is animated.
- Interrupt, reverse, or queue transitions according to explicit policy.
- Keep authentication controls usable while background effects fail or load.
- Provide focus order and keyboard navigation across the composed scene.
- Apply Theme tokens to layout and visual layer configuration.

Scene must not:

- Call D-Bus or greetd directly.
- Interpret PAM prompt text to decide authentication rules.
- Retry authentication because an animation ended.
- Store the password or forward it to a Visual.
- Reimplement the Feature state machine.
- Depend on a concrete Live2D or shader implementation.

Scene may expose user-intent callbacks to Feature, for example:

```text
Scene callback -> Feature command

selectUser(userId)                -> SelectUser
submitUsername(username)          -> BeginAuthentication
submitPrompt(response)            -> RespondToPrompt
cancelAuthentication()            -> CancelAuthentication
selectSession(sessionId)          -> SelectSession
startSession()                    -> StartSelectedSession
requestPowerAction(action)        -> RequestPowerAction
```

These callbacks are commands, not direct service calls. Feature remains the
owner of validation, lifecycle, and backend communication.

### 4.3 Visual: Rendering Implementations

Visual contains concrete visual implementations. A Visual consumes a stable
rendering context and does not know why a state changed.

Examples include:

- Static image or gradient-free wallpaper.
- Live2D character renderer.
- GPU shader background.
- Video background.
- Particle or ambient effect layer.
- Vector decoration layer.
- Reduced-motion or low-performance fallback layer.

Every Visual should expose a small lifecycle contract conceptually equivalent
to:

```text
prepare(resources, size)
update(context)
pause()
resume()
dispose()
```

Visual requirements:

- The visual state is driven by `VisualContext`, not by backend enums.
- Resource loading and disposal are explicit.
- A failed or slow effect cannot block login controls.
- The renderer has a static fallback.
- GPU/resource failure is reported as a visual diagnostic, not as an
  authentication failure.
- Visual layers do not log prompts, usernames, passwords, or D-Bus payloads.
- The layer has stable dimensions and does not cause layout jumps while assets
  load.

Visual performance is subordinate to authentication usability. A background
effect may be paused, reduced, or removed while text input, focus feedback,
error feedback, and power controls must remain responsive.

### 4.4 Theme: Design Tokens

Theme is a data-only design system. It should be immutable from the point of
view of a rendered frame and should not contain business decisions.

Theme token groups:

```text
Color       background, surface, text, accent, error, focus, disabled
Typography  family, size, weight, line height, text scale rules
Spacing     page inset, control gap, section gap, overlay inset
Shape       radius, border width, shadow/elevation policy
Effect      blur amount, opacity, scrim strength, particle intensity
Motion      duration, easing, reduced-motion alternatives
Layout      maximum content width, control height, safe-area inset
```

Theme must not decide:

- Whether authentication is allowed.
- Whether a session is available.
- Whether a prompt is secret.
- Whether a power operation is authorized.
- Which layer is currently visible.

Those are Feature or Scene decisions. Theme only supplies the values used to
express them.

Theme should also include accessibility-related tokens or policies for
contrast, focus indication, text scaling, keyboard navigation, and reduced
motion. These are presentation constraints, not optional decoration.

## 5. Three State Domains

The frontend should not use one large enum for all state. There are at least
three distinct domains.

### 5.1 Backend and Protocol State

This is the state defined by the backend and D-Bus contract. It exists to
protect authentication and session semantics.

```text
Idle
CreatingSession
PromptPending
WaitingForInput
SubmittingResponse
Authenticated
ResolvingSession
StartingSession
HandingOff
Cancelling
Failed
```

This state must remain compatible with the backend contract. It may be stored
inside the Feature model as a raw protocol field for diagnostics and precise
event handling.

### 5.2 Presentation State

Presentation state is a frontend projection designed for Scene and Visual. It
should be stable and understandable without knowing greetd terminology.

An example projection is:

```text
AuthIdle
AuthUserSelection
AuthSubmitting
AuthPrompting
AuthError
AuthHandingOff
ServiceUnavailable
```

User and session selection are local presentation choices. They do not mean
that PAM or greetd has entered a new protocol phase. The backend receives the
selected user when authentication begins and the selected session only when
the authenticated attempt is handed off with `StartSession`.

### 5.3 Local Interaction and Scene State

This state is owned by the Flutter UI and can change without any backend
event:

```text
focusedField
isKeyboardVisible
isPasswordRevealed
hoveredControl
activeDialog
currentTransition
backgroundLoadState
reducedMotionEnabled
```

This state must not be used to infer backend success or failure. For example,
finishing an `AuthError -> AuthIdle` fade does not reset the backend attempt;
only a Feature command can do that.

### 5.4 Orthogonal Service, Catalog, and Power State

Authentication, service availability, session catalog loading, and power
operations are independent concerns. They may affect the visual composition,
but they should not be merged into the authentication enum.

```text
ServiceState:  Starting -> Ready -> Unavailable -> Reconnecting -> Ready
CatalogState:  Empty -> Loading -> Ready
                         \-> Refreshing -> Ready
                         \-> Failure -> Degraded
PowerState:    Idle -> Authorizing -> Executing -> Succeeded / Failed
```

This allows, for example, a power menu error to appear as an overlay without
turning a valid authentication transaction into `AuthError`.

## 6. The `GreeterSceneSlots` Contract

`GreeterSceneSlots` is the typed semantic boundary between Feature and Scene.
It is an immutable aggregate snapshot, not a service locator and not a bag of
arbitrary values. The live Scene consumes the same projection through narrow
typed `ValueListenable` values so unrelated regions do not rebuild together.

The exact Dart syntax can be chosen during implementation, but the conceptual
shape should be close to:

```text
GreeterSceneSlots {
  service: ServicePresentationState
  authPrompt: AuthPromptSlots
  accountPicker: AccountPickerSlots
  sessionPicker: SessionPickerSlots
  continueAction: ContinueSlots
  power: PowerSlots
  background: BackgroundSlots
}
```

The current Flutter implementation exposes the corresponding region streams:

```text
ValueListenable<ServiceSlots>
ValueListenable<AuthPromptSlots>
ValueListenable<AccountPickerSlots>
ValueListenable<SessionPickerSlots>
ValueListenable<ContinueSlots>
ValueListenable<PowerSlots>
ValueListenable<BackgroundSlots>
```

`SceneHost` owns the stable layer order. `SceneRegion<T>` connects one typed
slot to one build boundary. Account selection therefore updates the account
picker and the Continue action, while power state updates only the power
region. The prompt region does not carry the transient response value.

Each nested value should be immutable and typed. A possible authentication
projection is:

```text
AuthPresentationState {
  mode: AuthMode
  selectedUserId: UserId?
  selectedUserName: DisplayName?
  attemptGeneration: AttemptGeneration?
  canSubmit: bool
  canCancel: bool
  error: DisplayError?
}
```

Prompt data should be explicit:

```text
PromptSlots {
  kind: PromptKind       // visible, secret, info, error
  label: String
  inputMode: PromptInputMode
  canSubmit: bool
  isSubmitting: bool
}
```

The prompt slots contain display metadata only. They must not contain the
current response value, password, OTP, or any opaque transport object. The
input widget keeps the response transiently and sends it to Feature through a
command callback.

A scene snapshot may also contain visual hints, but those hints must remain
semantic:

```text
BackgroundSlots {
  mood: BackgroundMood       // calm, waiting, active, success, error
  intensity: double          // bounded, presentation-only value
  allowAnimation: bool
  preferredVariant: String?
}
```

`preferredVariant` may select a theme-owned visual variant, but it must not be
an arbitrary asset path supplied by the backend or user input.

### 6.1 Snapshot and Effect Separation

Persistent rendering data and one-shot actions should be separate:

```text
GreeterSceneSlots  // latest aggregate state; safe to rebuild from at any time

SceneHost / SceneRegion  // stable layer order and narrow build boundaries

FeatureEffect      // one-shot event
  RequestFocus(field)
  ShowNotice(message)
  PlayTransition(name)
  ExitAfterHandoff
```

A Scene must be able to reconstruct the current screen from the latest slots.
It must not depend on having observed every historical event. Effects may be
lost during process restart, but the persistent snapshot must still describe
the correct current state. `ValueListenableBuilder` limits widget builds;
`RepaintBoundary` limits raster repaint propagation. Neither mechanism replaces
the other, and neither should be added to every small text or button widget.

### 6.2 Generation and Stale Event Handling

The Feature layer should retain the backend `attempt_id` or an equivalent
generation token. Signals and asynchronous results belonging to an older
attempt must not update the current slots.

The expected rule is:

```text
receive event
    |
    +-- event generation == current generation -> apply
    |
    +-- event generation != current generation -> discard safely
```

The Scene does not perform this security or transaction check. It receives
already-filtered presentation state from Feature.

## 7. Feature State Projection

The projection from protocol state to presentation state should be explicit
and tested as a pure function. An example mapping is:

| Backend state or event | Presentation state | Scene implication |
| --- | --- | --- |
| `Idle` | `AuthUserSelection` | Show independent user and session selection |
| `CreatingSession` | `AuthSubmitting` | Disable duplicate submission, show progress |
| `WaitingForInput` with `visible` or `secret` prompt | `AuthPrompting` | Focus prompt input |
| `SubmittingResponse` | `AuthSubmitting` | Keep prompt visible, prevent duplicate response |
| `Authenticated` | `AuthSubmitting` | Start the already selected backend-validated session |
| `ResolvingSession` or `StartingSession` | `AuthSubmitting` | Lock session action and show progress |
| `HandingOff` | `AuthHandingOff` | Play exit transition, then terminate UI |
| `Failed` with display-safe detail | `AuthError` | Preserve error and offer retry |
| backend unavailable | `ServiceUnavailable` | Keep controls coherent and expose recovery |

This table is a presentation policy, not a replacement for the backend state
machine. The mapping must preserve enough information to decide whether a
response, cancellation, retry, or session selection is valid.

## 8. Scene Composition

The initial Scene should use a stable stack with explicit ownership:

```text
RootScene
├── BackgroundScene
│   ├── StaticFallbackVisual
│   └── OptionalAnimatedVisual
├── AmbientOverlay
├── MainContentScene
│   ├── UserSelection
│   ├── AuthenticationForm
│   └── SessionSelection
├── PromptOverlay
├── ErrorOverlay
├── PowerOverlay
└── SystemStatusOverlay
```

The exact widget names are implementation details. The ownership rules are
not:

- Background layers never own authentication controls.
- Overlays may cover background content, but must not make the primary input
  unreachable.
- Error and prompt overlays must have a deterministic focus target.
- Power controls must remain independently addressable.
- The main content must have stable constraints even when a visual asset is
  loading.

### 8.1 Transition Policy

Scene transitions should be state-driven and interruptible. A transition must
not be used as a hidden command queue.

Example policies:

```text
AuthIdle -> AuthPrompting
  fade background toward active mood
  move prompt into place
  request keyboard focus

AuthPrompting -> AuthSubmitting
  keep the prompt visible
  replace input action with progress state

AuthSubmitting -> AuthPrompting
  preserve the prompt container
  update label and input mode
  request focus only when the new prompt needs input

AuthPrompting -> AuthError
  keep the user's context visible
  show display-safe error
  return focus to the retry action or prompt

Authenticated -> AuthSubmitting
  start the already selected session
  keep session choice independent from authentication

AuthHandingOff -> exit
  play bounded exit animation
  terminate only after the backend has accepted handoff
```

Every transition needs an interruption policy. For example, a new error
should cancel an old success animation, while a late animation completion must
not reset the current slots.

Scene should compare semantic snapshots or consume explicit transition hints;
it should not infer business meaning from widget insertion order or animation
callbacks.

### 8.2 Layout Rules

The Scene layout must provide stable dimensions for controls, prompt fields,
icons, and visual surfaces. Dynamic content such as long usernames, PAM prompt
text, and translated error messages must wrap or truncate within explicit
constraints.

The layout must define:

- Minimum and maximum content width.
- Safe-area and edge insets.
- Minimum control height and focus ring space.
- Prompt text wrapping behavior.
- Error text maximum width and overflow behavior.
- Behavior under text scaling and keyboard appearance.
- Behavior when the window is very wide, very short, or resized.

The background is allowed to crop or reduce quality to fit the viewport. The
credential form is not allowed to become unreachable because the background
needs more space.

### 8.3 Normalized Layout, Display Context, and Scene Authoring

Scene geometry must not depend on one fixed output resolution such as
`1920x1080`. The authoring coordinate system uses normalized values relative to
the current display safe area:

```text
x, y, width, height: 0.0 .. 1.0
```

The runtime converts normalized geometry to logical Flutter pixels for each
display. Backgrounds may use the full viewport with an explicit crop policy;
interactive controls use the safe area and intrinsic widget dimensions. A
scene must declare how it behaves for unusual aspect ratios rather than
silently stretching controls:

```text
crop | letterbox | reflow
```

The display environment is separate from Feature authentication state. It may
contain the display ID, logical and physical size, scale factor, refresh rate,
rotation, and output arrangement. Scene consumes this environment; Feature
does not.

Multi-display composition must not assume that all outputs share one canvas.
The initial policy is one primary display for login controls and optional
background or status layers on secondary displays. A per-display Scene can be
added later without changing the authentication contract.

The scene authoring editor is a separate tool. It edits a serializable scene
document, previews supported presentation states, and exports typed scene data
and bundled assets for the application. Production UI must not load arbitrary
scripts or executable components at runtime.

Each visual layer may define:

```text
position:    x, y, z
rotation:    rotationX, rotationY, rotationZ
scale:       scaleX, scaleY, scaleZ
pivot:       normalized anchor point
renderOrder: explicit draw order
```

`z` is spatial depth and `renderOrder` is draw order; they are separate
properties. The default scene is flat with zero depth and zero rotation. The
first 2.5D renderer only needs transformed image and widget planes with
bounded perspective. Full 3D meshes, lighting, and arbitrary cameras are out
of scope.

## 9. Visual Runtime Rules

Animated visuals are optional enhancements around a mandatory functional core.

### 9.1 Loading and Fallback

Each non-trivial Visual should have these states:

```text
Unavailable -> Loading -> Ready
                  \-> Failed -> StaticFallback
```

The Feature auth state must continue to work in every Visual state. A shader
compile error, missing video file, unsupported GPU feature, or Live2D asset
failure is a presentation diagnostic and must not block login.

### 9.2 Resource Ownership

The Scene creates and disposes Visuals. Feature does not own GPU resources.
Visuals must not hold a D-Bus client, an authentication controller, or a
reference to a password field.

Asset paths should come from trusted Theme or application configuration. They
must not be derived from raw backend strings without validation.

Static artwork should be composed from multiple trusted layers rather than
flattening the whole login UI into one bitmap. Text, buttons, password fields,
focus targets, and other interactive controls remain native Flutter widgets.
Image layers may provide backgrounds, character art, panel frames, decoration,
and state-specific overlays. Missing or unsupported artwork must fall back to a
usable static layer.

### 9.3 Performance and Reduced Motion

The visual runtime should support:

- Reduced-motion mode.
- A low-power mode.
- A static background fallback.
- Pause when the window is not visible or is handing off.
- Bounded frame work and resource memory.
- A separate diagnostic path for dropped frames or renderer failure.

Authentication input, keyboard focus, error feedback, and power controls have
priority over ambient animation.

## 10. D-Bus and Security Boundary

The Flutter D-Bus client should be hidden behind a Feature port. The rest of
the Flutter application should not depend on generated signatures, raw bus
names, or transport exceptions.

Conceptually:

```text
Scene callback
    -> Feature command
    -> GreeterGateway
    -> D-Bus adapter
    -> io.mozais.Greeter1
```

The reverse path is:

```text
io.mozais.Greeter1 signal/reply
    -> D-Bus adapter
    -> Feature reducer/projection
    -> GreeterSceneSlots
    -> Scene transition
```

Security rules:

1. Passwords and OTP values only exist in the short-lived input path used to
   call `Respond(attempt_id, response)`.
2. Passwords and OTP values never enter `GreeterSceneSlots`, Scene state,
   Visual context, logs, analytics, or error messages.
3. Prompt text may be displayed, but raw secret responses must never be
   re-emitted in a signal or diagnostic string.
4. The UI sends `session_id`, not arbitrary command or environment data.
5. The UI uses `attempt_id` for every state-changing authentication action.
6. A D-Bus disconnect must leave the backend responsible for cancelling the
   active transaction; the UI must not assume that its process exit is enough.
7. Power operations remain backend-mediated and are not implemented by shell
   commands in the Flutter process.
8. Biometric data, camera frames, fingerprint data, and biometric templates
   never enter Flutter state, scene documents, logs, or D-Bus signals.
9. The UI may display a provider-supplied, display-safe authentication factor
   or progress state, but must not infer it from arbitrary prompt text.

## 11. Error Model

Errors should be classified before they reach Scene:

```text
UserInputError
  invalid username, empty response, invalid local selection

AuthenticationError
  rejected credentials, PAM-visible authentication failure

TransportError
  D-Bus unavailable, greetd timeout, socket failure, malformed frame

SessionError
  unavailable session, invalid desktop entry, failed session start

PowerError
  authorization failure, unsupported action, logind failure

VisualError
  asset failure, shader failure, unsupported renderer
```

Only display-safe, user-appropriate information should cross into
`GreeterSceneSlots`. Internal transport details should remain available to
diagnostics without being exposed as raw user-facing text.

The Scene should not have to know whether an `AuthError` came from a PAM
failure or a D-Bus timeout. If the distinction changes the available recovery
action, Feature should expose that distinction as a typed recovery policy.

## 12. Testing Strategy

Testing should follow the same boundaries as the architecture.

### 12.1 Feature Unit Tests

Use fake ports and pure state transitions to cover:

- Initial state and user selection.
- Begin authentication and attempt generation.
- Repeated visible and secret prompts.
- Informational and error prompts that receive automatic empty responses.
- Successful authentication and session selection.
- Stale prompt or response events.
- Cancellation and client disconnect projection.
- Retry after a display-safe failure.
- Backend unavailable and reconnecting states.
- Independent power state changes.

These tests should assert both the resulting slots and emitted effects.

### 12.2 Scene Widget and Golden Tests

Use fixed `GreeterSceneSlots` fixtures and fake effect sinks. Cover:

- User selection.
- Username editing.
- Secret prompt.
- Multi-step prompt replacement.
- Submitting state with controls disabled correctly.
- Error state and retry focus.
- Session selection.
- Power overlay.
- Service unavailable overlay.
- Small, wide, short, and text-scaled layouts.
- Reduced-motion mode.

Scene tests must not need a D-Bus daemon or greetd socket.

### 12.3 Visual Contract Tests

Each Visual implementation should be testable with a fake or headless
renderer where possible. Validate:

- It accepts every supported `VisualContext` state.
- It can load, fail, fall back, pause, resume, and dispose.
- It does not change layout dimensions while loading.
- It does not block control input.
- It respects reduced-motion and low-power settings.

### 12.4 Integration Tests

Keep real boundaries where they provide meaningful confidence:

```text
real D-Bus client
    -> private/session bus
    -> real Rust backend
    -> fake greetd Unix socket
```

These tests should cover real method signatures, signals, attempt IDs,
disconnect behavior, stale responses, and session handoff. The greetd socket
transport may be fake, but the D-Bus transport and backend process should be
real for integration coverage.

Real PAM and real login handoff tests should be isolated to a VM, spare TTY,
or disposable account because they can terminate or replace the active login
session.

## 13. Proposed Flutter Organization

The following structure is a starting point. Names may change, but the
ownership boundaries should remain:

```text
lib/
├── main.dart
├── app/
│   ├── app.dart
│   └── app_theme.dart
├── feature/
│   └── greeter/
│       ├── greeter_feature.dart
│       ├── greeter_state.dart
│       ├── greeter_slots.dart
│       ├── greeter_effect.dart
│       ├── greeter_commands.dart
│       └── ports/
│           ├── greeter_gateway.dart
│           └── power_gateway.dart
├── infrastructure/
│   └── dbus/
│       ├── greeter_dbus_gateway.dart
│       └── dbus_error_mapper.dart
├── scene/
│   └── greeter_scene/
│       ├── greeter_scene.dart
│       ├── scene_transition.dart
│       ├── scene_stack.dart
│       └── layout/
├── visual/
│   ├── visual_layer.dart
│   ├── static_background.dart
│   ├── live2d_background.dart
│   ├── shader_background.dart
│   └── visual_fallback.dart
├── display/
│   ├── display_environment.dart
│   └── display_catalog.dart
├── theme/
│   ├── theme_tokens.dart
│   ├── color_tokens.dart
│   ├── motion_tokens.dart
│   └── layout_tokens.dart
└── shared/
    ├── ids.dart
    ├── display_error.dart
    └── result.dart
```

The D-Bus gateway is infrastructure. It should implement Feature ports and
remain replaceable by a fake gateway in unit tests. Scene and Visual should
never import the infrastructure directory.

## 14. Implementation Order

The implementation should proceed in small vertical slices:

### Phase 1: Contracts and Pure Models

1. Define typed frontend representations for users, sessions, prompts,
   authentication presentation state, service state, and power state.
2. Define `GreeterSceneSlots` and `FeatureEffect`.
3. Define Feature commands and gateway interfaces.
4. Add pure projection tests with no Flutter rendering.

### Phase 2: Real Backend Client

1. Implement the D-Bus gateway behind the Feature ports.
2. Map D-Bus errors and signals into typed backend events.
3. Enforce local attempt-generation checks.
4. Validate against the existing private-bus backend integration path.

### Phase 3: Functional Scene

1. Build a static Scene using normalized geometry and explicit constraints.
2. Connect user actions to Feature commands.
3. Implement user selection, authentication prompt, error, and session
   selection flows.
4. Add focus, keyboard navigation, text scaling, and reduced-motion support.

### Phase 4: Theme and Visuals

1. Extract all visual constants into Theme tokens.
2. Add a static background as the mandatory baseline.
3. Add normalized scene geometry and static image layers.
4. Add the separate scene authoring editor and typed export path.
5. Add animated Visual implementations behind stable interfaces.
6. Add load failure, low-power, and reduced-motion fallback behavior.

### Phase 5: End-to-End Hardening

1. Add real D-Bus and fake greetd integration coverage.
2. Test repeated prompts, stale signals, cancellation, and handoff.
3. Test visual failure independently from authentication failure.
4. Run the application in the actual greeter session and validate focus,
   keyboard input, GPU behavior, and session exit.

## 15. Acceptance Criteria

The architecture is considered implemented when all of the following are true:

- Scene can be tested entirely with fake `GreeterSceneSlots`.
- Feature can be tested without Flutter widgets or a running D-Bus daemon.
- Visual implementations can be replaced without changing Feature code.
- Theme changes do not alter authentication behavior.
- Authentication works with the static visual fallback enabled.
- No password or OTP value exists in scene slots, visual context, logs, or
  signals.
- Stale attempt events cannot update the current Scene.
- Repeated PAM prompts work without assuming a single password prompt.
- Power state is independent from authentication state.
- Session launch uses a backend-validated `session_id`.
- D-Bus disconnect and handoff behavior remain owned by the backend contract.
- Layout remains usable under resizing, text scaling, reduced motion, and
  visual resource failure.
- Scene geometry is expressed relative to a display safe area and remains
  usable on supported multi-display layouts.
- 2.5D layers default to flat rendering and preserve explicit draw order.
- Integration tests exercise real D-Bus/backend communication, while unit
  tests cover the Feature reducer and Scene transitions broadly.

## 16. Non-Goals

This architecture does not attempt to:

- Move PAM or greetd logic into Dart.
- Let the UI construct arbitrary desktop commands.
- Make every visual state a backend protocol state.
- Require Live2D, shaders, video, or GPU features for successful login.
- Make Theme a runtime dependency of the backend.
- Hide authentication errors behind visual animation.
- Replace the existing D-Bus protocol without an explicit contract change.

## 17. Open Decisions for Implementation

The following decisions can remain open until the first implementation slice,
provided they do not weaken the boundaries above:

- Which Dart state-management mechanism owns the Feature reducer.
- Whether D-Bus bindings are handwritten or generated from the XML contract.
- The concrete widget composition used by the first Scene.
- The asset format and runtime library for Live2D.
- The shader/video rendering implementation.
- Whether Theme is loaded from compile-time constants, a local file, or a
  packaged profile.
- The editor's authoring document format, provided its production export is
  typed and bundled at build time.

The following decisions should not remain open:

- Feature is the only layer that communicates with the backend.
- Scene receives typed semantic slots.
- Visuals do not own authentication or D-Bus behavior.
- Theme contains values, not business rules.
- Secrets do not enter Scene, Visual, Theme, logs, or signals.
- The static visual fallback always preserves a usable login flow.
- Biometric providers remain behind the backend/PAM boundary and expose only
  display-safe authentication interaction state.
