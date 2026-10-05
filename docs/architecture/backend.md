---
title: Backend code guide
description: Locate the Rust owners of process lifetime, authentication, and transport.
---

| Module | Responsibility |
| --- | --- |
| `main.rs` | Service startup, signals, bus loss, actor completion, and handoff shutdown |
| `service.rs` | D-Bus methods/signals, authentication actor, and system operations |
| `greetd.rs` | greetd protocol transport and mock implementation |
| `state.rs` | Authentication state and transaction data |
| `session_catalog.rs` | Desktop session discovery and launch data validation |
| `users.rs` | Account discovery |

The backend is currently an application crate. Its externally consumed interface
is the [D-Bus contract](../reference/dbus.md), rather than a Rust library API.
The `auth.rs` file is not declared by the current binary's module tree; follow
`service.rs` for the active authentication implementation.

## Lifetime and transactions

The process observes both service lifetime and authentication actor lifetime.
Shutdown stops accepting calls before cancelling active protocol work. Session
handoff must release the greeter so greetd can launch the selected desktop.

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
