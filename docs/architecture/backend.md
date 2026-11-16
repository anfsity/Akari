---
title: Backend code guide
description: Locate the Rust owners of process lifetime, authentication, and transport.
---

The Rust backend (`crates/akari-backend/`) is an application crate whose external interface is the [D-Bus contract](../reference/dbus.md).

The `crates/Cargo.toml` workspace shares one `Cargo.lock` and Rust edition with `akari-splash`. The crate is named `akari-backend`; its installed executable remains `backend`.

## Module map

| Module | Responsibility |
| --- | --- |
| `main.rs` | Entrypoint mode dispatch (D-Bus service vs. user-side session launcher), signal handling, and graceful shutdown |
| `service.rs` | `io.akari.Greeter1` D-Bus interface, authentication actor supervision, and `systemd-logind` power calls |
| `auth/handle.rs` | D-Bus-facing command handles and supervision of the actor task |
| `auth/actor.rs` | Single command queue, serialized acceptance, and operation replies |
| `auth/attempt.rs` | Attempt resources, snapshot/control publishing, cancellation, and signal ordering |
| `auth/flow.rs` | Serialized authentication and session-start protocol flows |
| `auth/caller_watch.rs` | Caller disconnect observation and cancellation without retaining the actor queue |
| `greetd/protocol.rs` | Protocol messages and shared transport errors |
| `greetd/transport.rs` | Real Unix socket transport, bounded framing, and zeroized credential buffers |
| `greetd/mock.rs` | Deterministic transport compiled only with the `mock` feature |
| `state.rs` | Pure authentication state machine (`AuthState`) and transition validation |
| `session_catalog.rs` | `.desktop` session discovery (`/usr/share/wayland-sessions`, `/usr/share/xsessions`) and `TryExec` validation |
| `session_launch.rs` | User login-shell forwarding (`--start-session` / `--exec-desktop`), argv preservation, locale checks, and session logs |
| `users.rs` | Interactive system account discovery |

## Lifetime & session handoff

### Service & actor lifecycle

- The process supervises both the D-Bus server and the single authentication actor (`auth/actor.rs`).
- Each authentication attempt receives a unique generation token (`attempt_id`). Signals and client calls must match the active `attempt_id`; cancellation or client disconnect invalidates it immediately.
- Power actions (`PowerAction`) run in an independent state domain without blocking or cancelling active PAM prompts.
- On shutdown (`SIGINT`, `SIGTERM`, or D-Bus disconnect), the backend stops accepting new calls, cancels in-flight `greetd` I/O, and releases the greeter so `greetd` can spawn the selected desktop.

### User desktop launch (`session_launch.rs`)

When `greetd` starts the authenticated session, it invokes the installed backend binary in two user-side stages (without starting the greeter's async runtime or D-Bus service):

1. **`--start-session`**: Captures native shell startup output in `startup-*.log` and execs the user's `$SHELL` in non-interactive login mode.
2. **`--exec-desktop`**: Re-entered from the initialized login shell; reads the JSON-encoded desktop `argv` from the environment, opens `session-*.log`, and execs the desktop command directly.

See [User session environment](../guides/greetd-testing.md#user-session-environment) for profile loading and log paths.

## Local code reference

Generate and browse local `rustdoc` pages (including private modules and items):

```sh
cargo doc --manifest-path crates/akari-backend/Cargo.toml --no-deps --document-private-items
```

Generated HTML is written to `crates/target/doc/`. Keep module-level invariants and resource ownership in `//!` and `///` doc comments, and document cross-module flows in this handbook.
