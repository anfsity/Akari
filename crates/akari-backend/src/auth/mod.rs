//! Serialized owner of authentication state and the greetd transaction.
//!
//! Commands serialize protocol I/O with state changes, avoiding separate locks
//! whose ordering could let a response mutate a replacement attempt. Watch
//! channels expose snapshots and cancellation handles without sharing mutable
//! transport ownership. Cancellation interrupts I/O outside the queue; cleanup
//! and replies still run through the actor, even when that queue is full.

mod actor;
mod attempt;
mod caller_watch;
mod handle;

pub(crate) use handle::{AuthActorHandle, AuthActorTask};
