---
title: Backend code guide
description: Locate the Rust owners of process lifetime, authentication, and transport.
---

| Module | Responsibility |
| --- | --- |
| `main.rs` | Select service startup or the user-side desktop executor; service signals and shutdown |
| `service.rs` | D-Bus methods/signals, authentication actor, and system operations |
| `auth.rs` | Serialized authentication transactions and greetd handoff, nested under `service` |
| `greetd.rs` | greetd protocol transport and mock implementation |
| `state.rs` | Authentication state and transaction data |
| `session_catalog.rs` | Desktop session discovery and launch data validation |
| `session_launch.rs` | Native login-shell forwarding, desktop argv, locale diagnostics, and user logs |
| `users.rs` | Account discovery |

The backend is currently an application crate. Its externally consumed interface
is the [D-Bus contract](../reference/dbus.md), rather than a Rust library API.
`service.rs` declares `auth.rs` as its private authentication module.

## Lifetime and transactions

The process observes both service lifetime and authentication actor lifetime.
Shutdown stops accepting calls before cancelling active protocol work. Session
handoff must release the greeter so greetd can launch the selected desktop.

The handoff forwards to the authenticated user's login shell, then re-enters the
same installed executable with `--exec-desktop`. That mode runs without the
greeter's async runtime or D-Bus service. Desktop arguments travel as JSON in
the greetd environment and are executed directly after native initialization.
The [real-login guide](../guides/greetd-testing.md#user-session-environment)
describes configuration, logs, and service-readiness boundaries.

Each authentication attempt has a generation token. UI signals and responses
must be associated with that attempt, and cancellation invalidates it. Power
requests use an independent state domain.

## Local code reference

For browsing Rust implementation details locally:

```sh
cargo doc --manifest-path backend/Cargo.toml --no-deps --document-private-items
```

The generated pages are under `backend/target/doc/`. Rustdoc reads `///` item
comments and `//!` module documentation. Explain protocol invariants and resource
ownership there; keep cross-module flows in this guide.

The public website currently publishes the theme SDK API. Backend code reference
can be added when there is a Rust API audience or a need for hosted contributor
reference.
