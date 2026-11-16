//! D-Bus-facing commands and the observed lifetime of the authentication actor.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

use tokio::{
    sync::{mpsc, oneshot, watch},
    task::JoinHandle,
};
use tokio_util::sync::CancellationToken;
use zbus::{fdo, object_server::SignalEmitter};

use super::{
    actor::run_actor,
    attempt::{AttemptControl, AuthSnapshot},
};
use crate::session_catalog::SessionEntry;

const COMMAND_BUFFER: usize = 16;
type CommandSender = mpsc::Sender<AuthCommand>;
pub(super) type BeginSequenceMap = Arc<Mutex<HashMap<String, u64>>>;

/// Handle used by D-Bus methods to communicate with the single authentication owner.
#[derive(Clone, Debug)]
pub(crate) struct AuthActorHandle {
    commands: CommandSender,
    snapshot: watch::Receiver<AuthSnapshot>,
    control: watch::Receiver<Option<AttemptControl>>,
    latest_begin: BeginSequenceMap,
}

impl AuthActorHandle {
    /// Starts the actor and returns the D-Bus-facing command and snapshot handle.
    pub(crate) fn spawn() -> (Self, AuthActorTask) {
        let (commands, receiver) = mpsc::channel(COMMAND_BUFFER);
        let (snapshot_sender, snapshot) = watch::channel(AuthSnapshot::idle());
        let (control_sender, control) = watch::channel(None);
        let shutdown = CancellationToken::new();
        let latest_begin = Arc::new(Mutex::new(HashMap::new()));
        let task = tokio::spawn(run_actor(
            receiver,
            commands.downgrade(),
            snapshot_sender,
            control_sender,
            Arc::clone(&latest_begin),
            shutdown.clone(),
        ));
        let runtime = AuthActorTask { task, shutdown };
        (
            Self {
                commands,
                snapshot,
                control,
                latest_begin,
            },
            runtime,
        )
    }

    /// Returns the latest state without waiting for greetd I/O.
    pub(crate) fn get_state(&self) -> fdo::Result<(String, String)> {
        if self.commands.is_closed() {
            return Err(fdo::Error::Failed(
                "authentication actor is unavailable".to_owned(),
            ));
        }
        let snapshot = self.snapshot.borrow().clone();
        Ok((snapshot.state, snapshot.detail))
    }

    /// Cancels the current attempt when it still matches `expected_attempt`.
    ///
    /// The token is cancelled before the command is queued so an in-flight
    /// transport operation observes cancellation while the actor preserves
    /// the ordering of state cleanup.
    pub(crate) fn interrupt_current(&self, expected_attempt: Option<&str>, caller: &str) -> bool {
        let control = self.control.borrow().clone();
        if let Some(control) = control
            && control.caller == caller
            && expected_attempt.is_none_or(|attempt| attempt == control.attempt_id)
        {
            control.cancellation.cancel();
            return true;
        }
        false
    }

    /// Replaces the current attempt and starts a new greetd transaction.
    pub(crate) async fn begin(
        &self,
        caller: String,
        username: String,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<String> {
        let sequence = {
            let mut sequences = self.latest_begin.lock().expect("begin sequence mutex");
            let next = sequences.get(&caller).copied().unwrap_or(0) + 1;
            sequences.insert(caller.clone(), next);
            next
        };
        self.interrupt_current(None, &caller);
        self.send_with(|reply| AuthCommand::Begin {
            caller,
            username,
            sequence,
            emitter,
            reply,
        })
        .await
    }

    /// Submits a UI response to the actor for the active prompt.
    pub(crate) async fn respond(
        &self,
        caller: String,
        attempt_id: String,
        response: zeroize::Zeroizing<String>,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<()> {
        self.send_with(|reply| AuthCommand::Respond {
            caller,
            attempt_id,
            response,
            emitter,
            reply,
        })
        .await
    }

    /// Requests cancellation of one specific authentication attempt.
    pub(crate) async fn cancel(
        &self,
        caller: String,
        attempt_id: String,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<()> {
        let allow_after_cleanup = self.interrupt_current(Some(&attempt_id), &caller);
        self.send_with(|reply| AuthCommand::Cancel {
            attempt_id,
            caller,
            allow_after_cleanup,
            emitter: Some(emitter),
            reply,
        })
        .await
    }

    /// Moves an authenticated attempt into backend-owned session resolution.
    pub(crate) async fn begin_session_resolution(
        &self,
        caller: String,
        attempt_id: String,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<()> {
        self.send_with(|reply| AuthCommand::BeginSessionResolution {
            caller,
            attempt_id,
            emitter,
            reply,
        })
        .await
    }

    /// Reports that the selected session disappeared during catalog lookup.
    pub(crate) async fn report_session_unavailable(
        &self,
        caller: String,
        attempt_id: String,
        detail: String,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<()> {
        self.send_with(|reply| AuthCommand::ReportSessionUnavailable {
            caller,
            attempt_id,
            detail,
            emitter,
            reply,
        })
        .await
    }

    /// Reports a session-catalog failure while retaining actor ownership of state.
    pub(crate) async fn fail_session_resolution(
        &self,
        caller: String,
        attempt_id: String,
        detail: String,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<()> {
        self.send_with(|reply| AuthCommand::FailSessionResolution {
            caller,
            attempt_id,
            detail,
            emitter,
            reply,
        })
        .await
    }

    /// Starts the backend-validated session through the active greetd transport.
    pub(crate) async fn start_session(
        &self,
        caller: String,
        attempt_id: String,
        session: SessionEntry,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<()> {
        self.send_with(|reply| AuthCommand::StartSession {
            caller,
            attempt_id,
            session,
            emitter,
            reply,
        })
        .await
    }

    /// Builds, enqueues, and awaits one typed command reply.
    async fn send_with<T, Build>(&self, build: Build) -> fdo::Result<T>
    where
        Build: FnOnce(oneshot::Sender<fdo::Result<T>>) -> AuthCommand,
    {
        send_command(&self.commands, build).await
    }
}

/// Owned by the process runtime so actor completion and failures are observed.
#[derive(Debug)]
pub(crate) struct AuthActorTask {
    pub(crate) task: JoinHandle<()>,
    shutdown: CancellationToken,
}

impl AuthActorTask {
    pub(crate) fn stop(&self) {
        self.shutdown.cancel();
    }
}

impl Drop for AuthActorTask {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Enqueues one typed command and waits for the actor's reply.
pub(super) async fn send_command<T, Build>(commands: &CommandSender, build: Build) -> fdo::Result<T>
where
    Build: FnOnce(oneshot::Sender<fdo::Result<T>>) -> AuthCommand,
{
    let (reply, receiver) = oneshot::channel();
    commands
        .send(build(reply))
        .await
        .map_err(|_| fdo::Error::Failed("authentication actor is unavailable".to_owned()))?;
    receiver
        .await
        .map_err(|_| fdo::Error::Failed("authentication actor stopped".to_owned()))?
}

/// Commands are serialized so state transitions and greetd I/O share one owner.
pub(super) enum AuthCommand {
    #[cfg(test)]
    Panic,
    Begin {
        caller: String,
        username: String,
        sequence: u64,
        emitter: SignalEmitter<'static>,
        reply: oneshot::Sender<fdo::Result<String>>,
    },
    Respond {
        caller: String,
        attempt_id: String,
        response: zeroize::Zeroizing<String>,
        emitter: SignalEmitter<'static>,
        reply: oneshot::Sender<fdo::Result<()>>,
    },
    Cancel {
        attempt_id: String,
        caller: String,
        allow_after_cleanup: bool,
        emitter: Option<SignalEmitter<'static>>,
        reply: oneshot::Sender<fdo::Result<()>>,
    },
    BeginSessionResolution {
        caller: String,
        attempt_id: String,
        emitter: SignalEmitter<'static>,
        reply: oneshot::Sender<fdo::Result<()>>,
    },
    ReportSessionUnavailable {
        caller: String,
        attempt_id: String,
        detail: String,
        emitter: SignalEmitter<'static>,
        reply: oneshot::Sender<fdo::Result<()>>,
    },
    FailSessionResolution {
        caller: String,
        attempt_id: String,
        detail: String,
        emitter: SignalEmitter<'static>,
        reply: oneshot::Sender<fdo::Result<()>>,
    },
    StartSession {
        caller: String,
        attempt_id: String,
        session: SessionEntry,
        emitter: SignalEmitter<'static>,
        reply: oneshot::Sender<fdo::Result<()>>,
    },
}

impl AuthCommand {
    pub(super) fn get_operation(&self) -> &'static str {
        match self {
            Self::Begin { .. } => "BeginAuthentication",
            Self::Respond { .. } => "Respond",
            Self::Cancel { .. } => "Cancel",
            Self::BeginSessionResolution { .. } => "ResolveSession",
            Self::ReportSessionUnavailable { .. } => "SessionUnavailable",
            Self::FailSessionResolution { .. } => "FailSessionResolution",
            Self::StartSession { .. } => "StartSession",
            #[cfg(test)]
            Self::Panic => "TestPanic",
        }
    }

    pub(super) fn get_caller(&self) -> Option<&str> {
        match self {
            Self::Begin { caller, .. }
            | Self::Respond { caller, .. }
            | Self::Cancel { caller, .. }
            | Self::BeginSessionResolution { caller, .. }
            | Self::ReportSessionUnavailable { caller, .. }
            | Self::FailSessionResolution { caller, .. }
            | Self::StartSession { caller, .. } => Some(caller),
            #[cfg(test)]
            Self::Panic => None,
        }
    }

    pub(super) fn get_attempt_id(&self) -> Option<&str> {
        match self {
            Self::Respond { attempt_id, .. }
            | Self::Cancel { attempt_id, .. }
            | Self::BeginSessionResolution { attempt_id, .. }
            | Self::ReportSessionUnavailable { attempt_id, .. }
            | Self::FailSessionResolution { attempt_id, .. }
            | Self::StartSession { attempt_id, .. } => Some(attempt_id),
            Self::Begin { .. } => None,
            #[cfg(test)]
            Self::Panic => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::AuthActorHandle;

    #[tokio::test]
    async fn actor_panic_is_observable_and_queries_fail() {
        let (actor, mut runtime) = AuthActorHandle::spawn();
        actor
            .commands
            .send(super::AuthCommand::Panic)
            .await
            .unwrap();
        assert!((&mut runtime.task).await.unwrap_err().is_panic());
        assert!(actor.get_state().is_err());
    }

    #[tokio::test]
    async fn dropping_handles_stops_actor() {
        let (actor, mut runtime) = AuthActorHandle::spawn();
        drop(actor);
        tokio::time::timeout(std::time::Duration::from_secs(1), &mut runtime.task)
            .await
            .unwrap()
            .unwrap();
    }

    #[tokio::test]
    async fn stopping_actor_closes_queries_and_commands() {
        let (actor, mut runtime) = AuthActorHandle::spawn();
        runtime.stop();
        (&mut runtime.task).await.unwrap();
        assert!(actor.get_state().is_err());
    }
}
