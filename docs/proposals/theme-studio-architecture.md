# Theme Studio Refactor Architecture

Status: architecture proposal. This document describes the target platform
that supports Theme Studio, the Flutter greeter, and the Rust backend. It does
not implement the refactor.

## 1. Product Shape

Mozais is a Theme Studio and greeter platform. A theme is an independent
Dart/Flutter package authored with the Mozais Theme SDK. Theme Studio provides
the development host, live preview, hot reload, diagnostics, state fixtures,
and performance tooling. The production greeter uses the same Host contract
and Theme Runtime.

```text
Theme package
      |
      v
Theme Studio host -> Flutter hot reload -> Theme Runtime
      |
      v
Production greeter -> Theme Runtime -> Greeter Host
```

Theme authors own backgrounds, layout, decoration, animation, typography,
assets, and custom visual components. Mozais supplies a small semantic host
surface for login behavior:

```text
Password
Account
Session
PowerAction
```

These host components own authentication state, secure input, focus, keyboard
navigation, semantics, and system actions. Theme code controls their visual
composition and presentation.

## 2. End-to-End Topology

```text
Linux system
  greetd / PAM
  system D-Bus / systemd-logind
  user catalog and desktop session files
          |
          v
Rust greeter launcher
  private session bus
  AuthActor
  GreeterService
  Flutter child process
          |
          v
Flutter Host Adapter
  typed snapshots, prompts, commands, and domain streams
          |
          v
Theme Runtime
  host components, custom theme widgets, layout, motion, input
          |
          v
Theme package
```

The Rust launcher is the greetd command and receives `GREETD_SOCK`. It starts
the private session bus, owns the Rust backend service, and supervises the
Flutter child. Flutter communicates with Rust through the private
`io.mozais.Greeter1` interface.

Theme Studio uses the same Flutter Host contract with a deterministic
`MockGreeterHost`. The editor can switch authentication states without starting
real PAM or greetd services.

## 3. Rust Backend

The Rust backend is the system control plane. It owns authentication
transactions, greetd transport, session discovery, power actions, and process
handoff.

### 3.1 Backend modules

```text
backend/src/main.rs
  launcher startup, private bus setup, Flutter child lifecycle

backend/src/greetd.rs
  greetd Unix socket transport and framed JSON protocol

backend/src/auth.rs
  AuthActor, command serialization, cancellation, attempt ownership

backend/src/state.rs
  pure authentication state machine and transition validation

backend/src/users.rs
  user catalog and display-safe user records

backend/src/session_catalog.rs
  desktop session discovery, validation, command and environment resolution

backend/src/service.rs
  io.mozais.Greeter1 D-Bus interface and signals
```

`AuthActor` is the single owner of the active greetd transaction. It serializes
commands, owns the transport and cancellation token, publishes a watch
snapshot, and associates every event with an `attempt_id`.

The authentication lifecycle is:

```text
Idle
  -> CreatingSession
  -> PromptPending
  -> WaitingForInput
  -> SubmittingResponse
  -> Authenticated
  -> ResolvingSession
  -> StartingSession
  -> HandingOff
```

The actor retains retry, cancellation, timeout, client disconnect, and stale
attempt handling as explicit transitions.

### 3.2 PAM conversation contract

The backend exposes the complete greetd/PAM conversation model:

```text
PromptKind:
  visible
  secret
  info
  error
```

Each prompt belongs to one transaction and receives a sequence number:

```text
Prompt(attempt_id, prompt_seq, kind, text)
Respond(attempt_id, prompt_seq, response)
```

One authentication attempt can contain multiple visible, secret, informational,
or error messages. Hardware and multi-factor progress can be represented by a
separate display-safe interaction event while the prompt protocol remains
stable.

Secret responses are handled in zeroizing Rust buffers, remain outside logs and
signals, and travel through the private method call that answers the active
prompt.

### 3.3 D-Bus and system services

Rust exposes a dedicated private session D-Bus service:

```text
Bus name:    io.mozais.Greeter
Object path: /io/mozais/Greeter
Interface:   io.mozais.Greeter1
```

The launcher gives Rust and Flutter the same private bus address. System D-Bus
is used by the Rust power controller for `systemd-logind` operations. Session
desktop files and user records are read and validated by Rust before their
display-safe fields reach Flutter.

## 4. Handoff Lifecycle

The launcher coordinates the final greeter-to-desktop transition:

```text
Flutter -> StartSession(attempt_id, session_id)
Rust -> resolve and validate session_id
Rust -> HandoffPreparing
Flutter -> play transition and send HandoffReady
Rust -> greetd start_session(cmd, env)
greetd -> success
Rust -> HandoffStarted
Rust -> close Flutter child and private bus
launcher -> exit
greetd -> start selected desktop session
```

The handoff protocol gives the UI a defined transition point and gives Rust
ownership of the final greetd request and process shutdown.

## 5. Flutter Host Contract

The Flutter side translates D-Bus values into typed domain objects:

```text
GreeterSnapshot
AuthPrompt
AuthenticationState
UserSummary
SessionSummary
PowerState
HandoffState
```

The Host Adapter maintains one ordered D-Bus signal stream and dispatches
domain-specific updates:

```text
AuthPrompt stream       -> Password component
Authentication stream   -> status and transition regions
User catalog stream     -> Account component
Session catalog stream  -> Session component
Power stream             -> PowerAction component
Handoff stream           -> transition overlay
```

The first implementation uses `package:dbus` with the private session bus. The
adapter performs typed decoding, event ordering, stale-attempt filtering, and
local domain notification before values reach Theme Runtime.

## 6. Theme SDK and Runtime

Theme packages use ordinary Dart/Flutter source:

```text
my_theme/
  pubspec.yaml
  lib/
    theme.dart
    components/
      background.dart
      account_layout.dart
      credential_decoration.dart
  assets/
  test/
  screenshots/
```

Theme SDK packages expose:

```text
mozais_theme_sdk
  Host components
  typed host state
  layout and animation helpers
  asset and font helpers
  local repaint boundaries
  theme diagnostics
```

Theme authors implement decorative components with Flutter widgets,
`CustomPainter`, animations, images, shaders, or other SDK-supported visual
techniques. Theme Runtime composes them with the four semantic host
components.

The runtime separates:

```text
Host region       authentication and system controls
Theme region      backgrounds and custom visual components
Input region      pointer capture and hit testing
Focus region      keyboard and accessibility traversal
Studio overlay    selection, handles, guides, and diagnostics
```

Each region has an independent state source and repaint boundary. Theme-local
state remains inside the theme component tree. Host snapshots update the
smallest affected region.

## 7. Theme Studio

Theme Studio is a Flutter development host around a Theme Project:

```text
ProjectSession
  files, assets, save, dirty state, undo/redo

PreviewSession
  MockGreeterHost, selected state, locale, viewport

CanvasController
  selection, pointer session, temporary transform

Inspector
  component properties, layout, motion, host bindings

DiagnosticsPanel
  compiler, layout, interaction, and performance results
```

Canvas editing treats one gesture as one transaction:

```text
pointer down -> capture initial geometry
pointer move -> update transient projection at frame cadence
pointer up   -> commit one project edit
```

The selected component and its editor overlay render from the same transient
projection. The persisted project model, dirty state, outline, and diagnostics
update when the gesture commits.

## 8. Development and Release Toolchain

Theme Studio uses the existing Dart and Flutter toolchain:

```text
mozais theme create <name>
mozais theme run
mozais theme test
mozais theme screenshot
mozais theme profile
mozais theme build
```

Development mode uses Flutter JIT and hot reload. The Host snapshot and Studio
selection state remain active while theme source changes are applied.

Release mode uses Flutter AOT and packages the selected theme with the greeter
build. The first implementation therefore gains mature Dart analysis,
debugging, hot reload, widget tests, golden tests, and release compilation
without maintaining a separate Theme language compiler.

## 9. Performance and Correctness

The platform defines measurable budgets:

```text
60 Hz target: 16.6 ms per frame
120 Hz target: 8.3 ms per frame
```

Theme Studio provides profile scenes and records build, layout, raster, GPU,
and pointer gesture p95/p99 timings.

Every theme can run a state matrix covering:

```text
dormant
account selection
password prompt
authentication error
session selection
power menu
service unavailable
```

The matrix runs across window sizes, DPI, locales, reduced-motion settings,
keyboard navigation, long text, empty catalogs, and screenshot fixtures.

Diagnostics cover layout constraints, overflow, component overlap, focus order,
hit regions, text clipping, and frame budget usage.

## 10. External AI Tool Bridge

AI is integrated as an external development tool through skills and tool calls.
The platform exposes project and test operations:

```text
theme_inspect
theme_validate
theme_preview
theme_screenshot
theme_apply_patch
theme_run_tests
theme_profile
```

An AI agent can inspect a theme package, create or edit components, render
specific Host states, compare screenshots, and run performance profiles. The
same Theme Studio diagnostics validate every generated change.

## 11. Platform Packages

The target package layout is:

```text
mozais_greeter_host
  Rust/Dart Host contract and typed display state

mozais_theme_sdk
  Theme author API and semantic components

mozais_theme_runtime
  Theme composition, layout, input, motion, and repaint regions

mozais_theme_studio
  Project editor, preview, Inspector, and diagnostics

mozais_theme_tooling
  Theme Generator, build commands, source mapping, and profiles

mozais_theme_test
  State, screenshot, interaction, and performance suites
```

The Rust backend remains the platform control plane. Theme packages remain the
visual extension layer. Theme Studio connects both through the typed Host
contract and the same Theme Runtime used by the greeter.

## 12. Delivery Stages

1. Stabilize the Rust Host contract, prompt sequence, private bus, and handoff
   lifecycle.
2. Extract the four semantic Host components into the Theme SDK.
3. Create one independent Dart/Flutter theme package and a Mock Greeter Host.
4. Build Theme Studio preview and Flutter hot reload around that package.
5. Add regional rendering, gesture transactions, state fixtures, and profiles.
6. Add screenshot, interaction, and performance conformance suites.
7. Add Theme Generator commands and the external AI tool bridge.

The existing detailed IPC specification remains the protocol reference:
`docs/dbus-contract.md`. This document defines the refactor-level relationship
between that backend, Theme Studio, and the production greeter.
