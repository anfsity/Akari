//! Serialized owner of authentication state and the greetd transaction.

use std::{sync::Arc, time::Duration};

use futures_util::StreamExt;
use tokio::{
    sync::{Notify, mpsc, oneshot, watch},
    time::timeout,
};
use tokio_util::sync::CancellationToken;
use zbus::{fdo, object_server::SignalEmitter};

use crate::{
    greetd::{GreetdError, GreetdResponse, GreetdTransport},
    session_catalog::SessionEntry,
    state::{AuthState, AuthStateMachine, BeginAuthenticationError, StateEvent},
};

const CANCEL_TIMEOUT: Duration = Duration::from_secs(1);
const COMMAND_BUFFER: usize = 16;

type CommandSender = mpsc::Sender<AuthCommand>;

/// Handle used by D-Bus methods to communicate with the single authentication owner.
#[derive(Clone, Debug)]
pub(super) struct AuthActorHandle {
    commands: CommandSender,
    snapshot: watch::Receiver<AuthSnapshot>,
    control: watch::Receiver<Option<AttemptControl>>,
}

impl AuthActorHandle {
    /// Starts the actor and returns the D-Bus-facing command and snapshot handle.
    pub(super) fn spawn(handoff: Arc<Notify>) -> Self {
        let (commands, receiver) = mpsc::channel(COMMAND_BUFFER);
        let (power_releases, release_receiver) = mpsc::unbounded_channel();
        let (snapshot_sender, snapshot) = watch::channel(AuthSnapshot::idle());
        let (control_sender, control) = watch::channel(None);
        tokio::spawn(run_actor(
            receiver,
            release_receiver,
            power_releases,
            commands.clone(),
            snapshot_sender,
            control_sender,
            handoff,
        ));
        Self {
            commands,
            snapshot,
            control,
        }
    }

    /// Returns the latest state without waiting for greetd I/O.
    pub(super) fn current_state(&self) -> (String, String) {
        let snapshot = self.snapshot.borrow().clone();
        (snapshot.state, snapshot.detail)
    }

    /// Cancels the current attempt when it still matches `expected_attempt`.
    ///
    /// The token is cancelled before the command is queued so an in-flight
    /// transport operation observes cancellation while the actor preserves
    /// the ordering of state cleanup.
    pub(super) fn interrupt_current(&self, expected_attempt: Option<&str>) -> bool {
        let control = self.control.borrow().clone();
        if let Some(control) = control
            && expected_attempt.is_none_or(|attempt| attempt == control.attempt_id)
        {
            control.cancellation.cancel();
            return true;
        }
        false
    }

    /// Replaces the current attempt and starts a new greetd transaction.
    pub(super) async fn begin(
        &self,
        caller: String,
        username: String,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<String> {
        self.interrupt_current(None);
        let (reply, receiver) = oneshot::channel();
        self.send(
            AuthCommand::Begin {
                caller,
                username,
                emitter,
                reply,
            },
            receiver,
        )
        .await
    }

    /// Submits a UI response to the actor for the active prompt.
    pub(super) async fn respond(
        &self,
        attempt_id: String,
        response: zeroize::Zeroizing<String>,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<()> {
        let (reply, receiver) = oneshot::channel();
        self.send(
            AuthCommand::Respond {
                attempt_id,
                response,
                emitter,
                reply,
            },
            receiver,
        )
        .await
    }

    /// Requests cancellation of one specific authentication attempt.
    pub(super) async fn cancel(
        &self,
        attempt_id: String,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<()> {
        let allow_after_cleanup = self.interrupt_current(Some(&attempt_id));
        let (reply, receiver) = oneshot::channel();
        self.send(
            AuthCommand::Cancel {
                expected_attempt: Some(attempt_id),
                expected_caller: None,
                allow_after_cleanup,
                emitter: Some(emitter),
                reply,
            },
            receiver,
        )
        .await
    }

    /// Moves an authenticated attempt into backend-owned session resolution.
    pub(super) async fn begin_session_resolution(
        &self,
        attempt_id: String,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<()> {
        let (reply, receiver) = oneshot::channel();
        self.send(
            AuthCommand::BeginSessionResolution {
                attempt_id,
                emitter,
                reply,
            },
            receiver,
        )
        .await
    }

    /// Reports that the selected session disappeared during catalog lookup.
    pub(super) async fn session_unavailable(
        &self,
        attempt_id: String,
        detail: String,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<()> {
        let (reply, receiver) = oneshot::channel();
        self.send(
            AuthCommand::SessionUnavailable {
                attempt_id,
                detail,
                emitter,
                reply,
            },
            receiver,
        )
        .await
    }

    /// Reports a session-catalog failure while retaining actor ownership of state.
    pub(super) async fn fail_session_resolution(
        &self,
        attempt_id: String,
        detail: String,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<()> {
        let (reply, receiver) = oneshot::channel();
        self.send(
            AuthCommand::FailSessionResolution {
                attempt_id,
                detail,
                emitter,
                reply,
            },
            receiver,
        )
        .await
    }

    /// Starts the backend-validated session through the active greetd transport.
    pub(super) async fn start_session(
        &self,
        attempt_id: String,
        session: SessionEntry,
        emitter: SignalEmitter<'static>,
    ) -> fdo::Result<()> {
        let (reply, receiver) = oneshot::channel();
        self.send(
            AuthCommand::StartSession {
                attempt_id,
                session,
                emitter,
                reply,
            },
            receiver,
        )
        .await
    }

    /// Reserves the actor while a power action uses the system D-Bus.
    pub(super) async fn reserve_power(&self) -> fdo::Result<PowerLease> {
        let (reply, receiver) = oneshot::channel();
        self.send(AuthCommand::AcquirePower { reply }, receiver)
            .await
    }

    /// Enqueues a command and waits for the result produced by the actor.
    async fn send<T>(
        &self,
        command: AuthCommand,
        receiver: oneshot::Receiver<fdo::Result<T>>,
    ) -> fdo::Result<T> {
        self.commands
            .send(command)
            .await
            .map_err(|_| fdo::Error::Failed("authentication actor is unavailable".to_owned()))?;
        receiver
            .await
            .map_err(|_| fdo::Error::Failed("authentication actor stopped".to_owned()))?
    }
}

/// Reservation held by a power action while it performs the system D-Bus call.
pub(super) struct PowerLease {
    release: mpsc::UnboundedSender<()>,
}

impl Drop for PowerLease {
    fn drop(&mut self) {
        let _ = self.release.send(());
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct AuthSnapshot {
    attempt_id: String,
    state: String,
    detail: String,
}

impl AuthSnapshot {
    fn idle() -> Self {
        Self {
            attempt_id: String::new(),
            state: AuthState::Idle.as_str().to_owned(),
            detail: String::new(),
        }
    }

    fn from_auth(auth: &AuthStateMachine, attempt_id: &str) -> Self {
        Self {
            attempt_id: attempt_id.to_owned(),
            state: auth.state().as_str().to_owned(),
            detail: auth.detail().to_owned(),
        }
    }
}

#[derive(Clone, Debug)]
struct AttemptControl {
    attempt_id: String,
    cancellation: CancellationToken,
}

/// Commands are serialized so state transitions and greetd I/O share one owner.
enum AuthCommand {
    Begin {
        caller: String,
        username: String,
        emitter: SignalEmitter<'static>,
        reply: oneshot::Sender<fdo::Result<String>>,
    },
    Respond {
        attempt_id: String,
        response: zeroize::Zeroizing<String>,
        emitter: SignalEmitter<'static>,
        reply: oneshot::Sender<fdo::Result<()>>,
    },
    Cancel {
        expected_attempt: Option<String>,
        expected_caller: Option<String>,
        allow_after_cleanup: bool,
        emitter: Option<SignalEmitter<'static>>,
        reply: oneshot::Sender<fdo::Result<()>>,
    },
    BeginSessionResolution {
        attempt_id: String,
        emitter: SignalEmitter<'static>,
        reply: oneshot::Sender<fdo::Result<()>>,
    },
    SessionUnavailable {
        attempt_id: String,
        detail: String,
        emitter: SignalEmitter<'static>,
        reply: oneshot::Sender<fdo::Result<()>>,
    },
    FailSessionResolution {
        attempt_id: String,
        detail: String,
        emitter: SignalEmitter<'static>,
        reply: oneshot::Sender<fdo::Result<()>>,
    },
    StartSession {
        attempt_id: String,
        session: SessionEntry,
        emitter: SignalEmitter<'static>,
        reply: oneshot::Sender<fdo::Result<()>>,
    },
    AcquirePower {
        reply: oneshot::Sender<fdo::Result<PowerLease>>,
    },
}

/// Mutable authentication resources owned exclusively by `run_actor`.
#[derive(Default)]
struct ActorState {
    auth: AuthStateMachine,
    transport: Option<GreetdTransport>,
    cancellation: Option<CancellationToken>,
    caller: Option<String>,
    caller_watcher: Option<CancellationToken>,
    power_busy: bool,
}

async fn run_actor(
    mut commands: mpsc::Receiver<AuthCommand>,
    mut power_releases: mpsc::UnboundedReceiver<()>,
    power_release_sender: mpsc::UnboundedSender<()>,
    command_sender: CommandSender,
    snapshots: watch::Sender<AuthSnapshot>,
    controls: watch::Sender<Option<AttemptControl>>,
    handoff: Arc<Notify>,
) {
    let mut actor = ActorState::default();
    loop {
        // Process lease releases in the same loop as D-Bus commands so a
        // completed power action cannot leave the actor permanently busy.
        let command = tokio::select! {
            command = commands.recv() => command,
            release = power_releases.recv() => {
                if release.is_some() {
                    actor.power_busy = false;
                    continue;
                }
                commands.recv().await
            }
        };
        let Some(command) = command else {
            break;
        };
        match command {
            AuthCommand::Begin {
                caller,
                username,
                emitter,
                reply,
            } => {
                let result = handle_begin(
                    &mut actor,
                    caller,
                    username,
                    emitter,
                    &snapshots,
                    &controls,
                    &command_sender,
                )
                .await;
                let _ = reply.send(result);
            }
            AuthCommand::Respond {
                attempt_id,
                response,
                emitter,
                reply,
            } => {
                let result = handle_respond(
                    &mut actor,
                    &attempt_id,
                    response,
                    emitter,
                    &snapshots,
                    &controls,
                )
                .await;
                let _ = reply.send(result);
            }
            AuthCommand::Cancel {
                expected_attempt,
                expected_caller,
                allow_after_cleanup,
                emitter,
                reply,
            } => {
                let result = cancel_current(
                    &mut actor,
                    expected_attempt.as_deref(),
                    expected_caller.as_deref(),
                    allow_after_cleanup,
                    emitter,
                    &snapshots,
                    &controls,
                )
                .await;
                let _ = reply.send(result);
            }
            AuthCommand::BeginSessionResolution {
                attempt_id,
                emitter,
                reply,
            } => {
                let result =
                    begin_session_resolution(&mut actor, &attempt_id, &emitter, &snapshots).await;
                let _ = reply.send(result);
            }
            AuthCommand::SessionUnavailable {
                attempt_id,
                detail,
                emitter,
                reply,
            } => {
                let result =
                    session_unavailable(&mut actor, &attempt_id, detail, &emitter, &snapshots)
                        .await;
                let _ = reply.send(result);
            }
            AuthCommand::FailSessionResolution {
                attempt_id,
                detail,
                emitter,
                reply,
            } => {
                let result = fail_session_resolution(
                    &mut actor,
                    &attempt_id,
                    detail,
                    &emitter,
                    &snapshots,
                    &controls,
                )
                .await;
                let _ = reply.send(result);
            }
            AuthCommand::StartSession {
                attempt_id,
                session,
                emitter,
                reply,
            } => {
                let result = handle_start_session(
                    &mut actor,
                    &attempt_id,
                    session,
                    emitter,
                    &snapshots,
                    &controls,
                    &handoff,
                )
                .await;
                let _ = reply.send(result);
            }
            AuthCommand::AcquirePower { reply } => {
                let result = if actor.power_busy {
                    Err(fdo::Error::Failed(
                        "power action is already in progress".to_owned(),
                    ))
                } else if is_active_authentication_state(actor.auth.state()) {
                    Err(fdo::Error::Failed(
                        "power action rejected while authentication is active".to_owned(),
                    ))
                } else {
                    actor.power_busy = true;
                    Ok(PowerLease {
                        release: power_release_sender.clone(),
                    })
                };
                let _ = reply.send(result);
            }
        }
    }

    let _ = cancel_current(&mut actor, None, None, false, None, &snapshots, &controls).await;
}

async fn handle_begin(
    actor: &mut ActorState,
    caller: String,
    username: String,
    emitter: SignalEmitter<'static>,
    snapshots: &watch::Sender<AuthSnapshot>,
    controls: &watch::Sender<Option<AttemptControl>>,
    commands: &CommandSender,
) -> fdo::Result<String> {
    if actor.power_busy {
        return Err(fdo::Error::Failed("power action is in progress".to_owned()));
    }
    cancel_current(actor, None, None, false, None, snapshots, controls).await?;

    let cancellation = CancellationToken::new();
    let watcher_token = CancellationToken::new();
    let attempt_id = actor
        .auth
        .begin_authentication(username.clone())
        .map_err(map_begin_authentication_error)?;
    actor.cancellation = Some(cancellation.clone());
    actor.caller = Some(caller.clone());
    actor.caller_watcher = Some(watcher_token.clone());
    publish_state(&actor.auth, &attempt_id, snapshots);
    let _ = controls.send(Some(AttemptControl {
        attempt_id: attempt_id.clone(),
        cancellation: cancellation.clone(),
    }));
    emit_state_best_effort(Some(&emitter), &snapshot(&actor.auth, &attempt_id)).await;
    spawn_caller_watcher(
        emitter.connection().clone(),
        caller,
        attempt_id.clone(),
        watcher_token,
        cancellation.clone(),
        commands.clone(),
    );

    // Connection and create_session are part of this actor command. A failed
    // or cancelled exchange therefore reaches cleanup before the next command.
    let transport = match GreetdTransport::connect(&cancellation).await {
        Ok(transport) => transport,
        Err(GreetdError::Cancelled) => {
            return Err(
                finish_cancelled(actor, &attempt_id, Some(&emitter), snapshots, controls).await,
            );
        }
        Err(error) => {
            return Err(
                fail_transaction(actor, &attempt_id, error, &emitter, snapshots, controls).await,
            );
        }
    };
    actor.transport = Some(transport);

    let response = request_create_session(actor, &username, &cancellation).await;
    let response = match response {
        Ok(response) => response,
        Err(GreetdError::Cancelled) => {
            return Err(
                finish_cancelled(actor, &attempt_id, Some(&emitter), snapshots, controls).await,
            );
        }
        Err(error) => {
            actor.transport.take();
            return Err(
                fail_transaction(actor, &attempt_id, error, &emitter, snapshots, controls).await,
            );
        }
    };

    consume_response(
        actor,
        &attempt_id,
        response,
        emitter,
        &cancellation,
        snapshots,
        controls,
    )
    .await?;
    Ok(attempt_id)
}

async fn handle_respond(
    actor: &mut ActorState,
    attempt_id: &str,
    response: zeroize::Zeroizing<String>,
    emitter: SignalEmitter<'static>,
    snapshots: &watch::Sender<AuthSnapshot>,
    controls: &watch::Sender<Option<AttemptControl>>,
) -> fdo::Result<()> {
    validate_attempt(&actor.auth, attempt_id)?;
    require_state(&actor.auth, AuthState::WaitingForInput)?;
    let cancellation = actor
        .cancellation
        .as_ref()
        .ok_or_else(|| {
            fdo::Error::Failed("authentication cancellation token is unavailable".to_owned())
        })?
        .clone();
    if actor.transport.is_none() {
        return Err(fdo::Error::Failed(
            "greetd transport is unavailable".to_owned(),
        ));
    }

    actor
        .auth
        .transition(StateEvent::ResponseSubmitted)
        .map_err(map_transition_error)?;
    publish_state(&actor.auth, attempt_id, snapshots);
    emit_state_best_effort(Some(&emitter), &snapshot(&actor.auth, attempt_id)).await;

    let result = request_post_response(actor, Some(response.as_str()), &cancellation).await;
    drop(response);
    let next_response = match result {
        Ok(response) => response,
        Err(GreetdError::Cancelled) => {
            return Err(
                finish_cancelled(actor, attempt_id, Some(&emitter), snapshots, controls).await,
            );
        }
        Err(error) => {
            actor.transport.take();
            return Err(
                fail_transaction(actor, attempt_id, error, &emitter, snapshots, controls).await,
            );
        }
    };

    consume_response(
        actor,
        attempt_id,
        next_response,
        emitter,
        &cancellation,
        snapshots,
        controls,
    )
    .await
    .map(|_| ())
}

async fn begin_session_resolution(
    actor: &mut ActorState,
    attempt_id: &str,
    emitter: &SignalEmitter<'static>,
    snapshots: &watch::Sender<AuthSnapshot>,
) -> fdo::Result<()> {
    validate_attempt(&actor.auth, attempt_id)?;
    require_state(&actor.auth, AuthState::Authenticated)?;
    actor
        .auth
        .transition(StateEvent::StartSessionRequested)
        .map_err(map_transition_error)?;
    publish_state(&actor.auth, attempt_id, snapshots);
    emit_state_best_effort(Some(emitter), &snapshot(&actor.auth, attempt_id)).await;
    Ok(())
}

async fn session_unavailable(
    actor: &mut ActorState,
    attempt_id: &str,
    detail: String,
    emitter: &SignalEmitter<'static>,
    snapshots: &watch::Sender<AuthSnapshot>,
) -> fdo::Result<()> {
    validate_attempt(&actor.auth, attempt_id)?;
    require_state(&actor.auth, AuthState::ResolvingSession)?;
    actor
        .auth
        .transition(StateEvent::SessionUnavailable { detail })
        .map_err(map_transition_error)?;
    publish_state(&actor.auth, attempt_id, snapshots);
    emit_state_best_effort(Some(emitter), &snapshot(&actor.auth, attempt_id)).await;
    Ok(())
}

async fn fail_session_resolution(
    actor: &mut ActorState,
    attempt_id: &str,
    detail: String,
    emitter: &SignalEmitter<'static>,
    snapshots: &watch::Sender<AuthSnapshot>,
    controls: &watch::Sender<Option<AttemptControl>>,
) -> fdo::Result<()> {
    validate_attempt(&actor.auth, attempt_id)?;
    require_state(&actor.auth, AuthState::ResolvingSession)?;
    let detail = display_detail(&detail);
    actor
        .auth
        .transition(StateEvent::ProtocolFailure {
            detail: detail.clone(),
        })
        .map_err(map_transition_error)?;
    publish_state(&actor.auth, attempt_id, snapshots);
    emit_state_best_effort(Some(emitter), &snapshot(&actor.auth, attempt_id)).await;
    detach_resources(actor, controls);
    Ok(())
}

async fn handle_start_session(
    actor: &mut ActorState,
    attempt_id: &str,
    session: SessionEntry,
    emitter: SignalEmitter<'static>,
    snapshots: &watch::Sender<AuthSnapshot>,
    controls: &watch::Sender<Option<AttemptControl>>,
    handoff: &Arc<Notify>,
) -> fdo::Result<()> {
    validate_attempt(&actor.auth, attempt_id)?;
    require_state(&actor.auth, AuthState::ResolvingSession)?;
    let cancellation = actor
        .cancellation
        .as_ref()
        .ok_or_else(|| {
            fdo::Error::Failed("authentication cancellation token is unavailable".to_owned())
        })?
        .clone();
    if actor.transport.is_none() {
        return Err(fdo::Error::Failed(
            "greetd transport is unavailable".to_owned(),
        ));
    }

    actor
        .auth
        .transition(StateEvent::SessionResolved)
        .map_err(map_transition_error)?;
    publish_state(&actor.auth, attempt_id, snapshots);
    emit_state_best_effort(Some(&emitter), &snapshot(&actor.auth, attempt_id)).await;

    let environment = session_environment(&session);
    let response = request_start_session(actor, &session.exec, &environment, &cancellation).await;
    let response = match response {
        Ok(response) => response,
        Err(GreetdError::Cancelled) => {
            return Err(
                finish_cancelled(actor, attempt_id, Some(&emitter), snapshots, controls).await,
            );
        }
        Err(error) => {
            actor.transport.take();
            return Err(
                fail_transaction(actor, attempt_id, error, &emitter, snapshots, controls).await,
            );
        }
    };

    match response {
        GreetdResponse::Success => {
            validate_attempt(&actor.auth, attempt_id)?;
            require_state(&actor.auth, AuthState::StartingSession)?;
            actor
                .auth
                .transition(StateEvent::SessionStarted)
                .map_err(map_transition_error)?;
            publish_state(&actor.auth, attempt_id, snapshots);
            emit_state_best_effort(Some(&emitter), &snapshot(&actor.auth, attempt_id)).await;
            detach_resources(actor, controls);
            schedule_handoff_after_reply(emitter.connection().clone(), Arc::clone(handoff));
            Ok(())
        }
        GreetdResponse::Error {
            error_type,
            description,
        } => {
            let detail = display_detail(&format!("{error_type}: {description}"));
            actor
                .auth
                .transition(StateEvent::SessionStartFailed {
                    detail: detail.clone(),
                })
                .map_err(map_transition_error)?;
            publish_state(&actor.auth, attempt_id, snapshots);
            emit_state_best_effort(Some(&emitter), &snapshot(&actor.auth, attempt_id)).await;
            detach_resources(actor, controls);
            Err(fdo::Error::Failed(detail))
        }
        GreetdResponse::AuthMessage { .. } => {
            actor.transport.take();
            Err(fail_transaction(
                actor,
                attempt_id,
                GreetdError::UnexpectedResponse(
                    "greetd returned an authentication message while starting a session".to_owned(),
                ),
                &emitter,
                snapshots,
                controls,
            )
            .await)
        }
    }
}

async fn consume_response(
    actor: &mut ActorState,
    attempt_id: &str,
    mut response: GreetdResponse,
    emitter: SignalEmitter<'static>,
    cancellation: &CancellationToken,
    snapshots: &watch::Sender<AuthSnapshot>,
    controls: &watch::Sender<Option<AttemptControl>>,
) -> fdo::Result<AuthenticationOutcome> {
    // One greetd response can require several follow-up frames: visible and
    // secret prompts wait for the UI, while informational messages are
    // acknowledged automatically and continue the same transaction.
    loop {
        if cancellation.is_cancelled() {
            return Err(
                finish_cancelled(actor, attempt_id, Some(&emitter), snapshots, controls).await,
            );
        }
        match response {
            GreetdResponse::Success => {
                validate_attempt(&actor.auth, attempt_id)?;
                actor
                    .auth
                    .transition(StateEvent::AuthenticationSucceeded)
                    .map_err(map_transition_error)?;
                publish_state(&actor.auth, attempt_id, snapshots);
                emit_state_best_effort(Some(&emitter), &snapshot(&actor.auth, attempt_id)).await;
                return Ok(AuthenticationOutcome::Authenticated);
            }
            GreetdResponse::Error {
                error_type,
                description,
            } => {
                let detail = display_detail(&format!("{error_type}: {description}"));
                actor
                    .auth
                    .transition(StateEvent::AuthenticationFailed {
                        detail: detail.clone(),
                    })
                    .map_err(map_transition_error)?;
                publish_state(&actor.auth, attempt_id, snapshots);
                emit_state_best_effort(Some(&emitter), &snapshot(&actor.auth, attempt_id)).await;
                detach_resources(actor, controls);
                return Err(fdo::Error::Failed(detail));
            }
            GreetdResponse::AuthMessage {
                auth_message_type,
                auth_message,
            } => {
                validate_attempt(&actor.auth, attempt_id)?;
                actor
                    .auth
                    .transition(StateEvent::AuthMessage)
                    .map_err(map_transition_error)?;
                publish_state(&actor.auth, attempt_id, snapshots);
                emit_state_best_effort(Some(&emitter), &snapshot(&actor.auth, attempt_id)).await;
                if cancellation.is_cancelled() {
                    return Err(finish_cancelled(
                        actor,
                        attempt_id,
                        Some(&emitter),
                        snapshots,
                        controls,
                    )
                    .await);
                }
                emit_prompt_best_effort(&emitter, attempt_id, &auth_message_type, auth_message)
                    .await;
                match auth_message_type.as_str() {
                    "visible" | "secret" => {
                        if cancellation.is_cancelled() {
                            return Err(finish_cancelled(
                                actor,
                                attempt_id,
                                Some(&emitter),
                                snapshots,
                                controls,
                            )
                            .await);
                        }
                        actor
                            .auth
                            .transition(StateEvent::PromptNeedsInput)
                            .map_err(map_transition_error)?;
                        publish_state(&actor.auth, attempt_id, snapshots);
                        emit_state_best_effort(Some(&emitter), &snapshot(&actor.auth, attempt_id))
                            .await;
                        if cancellation.is_cancelled() {
                            return Err(finish_cancelled(
                                actor,
                                attempt_id,
                                Some(&emitter),
                                snapshots,
                                controls,
                            )
                            .await);
                        }
                        return Ok(AuthenticationOutcome::WaitingForInput);
                    }
                    "info" | "error" => {
                        actor
                            .auth
                            .transition(StateEvent::PromptAutoResponse)
                            .map_err(map_transition_error)?;
                        publish_state(&actor.auth, attempt_id, snapshots);
                        emit_state_best_effort(Some(&emitter), &snapshot(&actor.auth, attempt_id))
                            .await;
                        let cancellation = actor
                            .cancellation
                            .as_ref()
                            .ok_or_else(|| {
                                fdo::Error::Failed(
                                    "authentication cancellation token is unavailable".to_owned(),
                                )
                            })?
                            .clone();
                        response = match request_post_response(actor, None, &cancellation).await {
                            Ok(response) => response,
                            Err(GreetdError::Cancelled) => {
                                return Err(finish_cancelled(
                                    actor,
                                    attempt_id,
                                    Some(&emitter),
                                    snapshots,
                                    controls,
                                )
                                .await);
                            }
                            Err(error) => {
                                actor.transport.take();
                                return Err(fail_transaction(
                                    actor, attempt_id, error, &emitter, snapshots, controls,
                                )
                                .await);
                            }
                        };
                    }
                    _ => {
                        actor.transport.take();
                        return Err(fail_transaction(
                            actor,
                            attempt_id,
                            GreetdError::UnexpectedResponse(format!(
                                "unsupported authentication message type: {auth_message_type}"
                            )),
                            &emitter,
                            snapshots,
                            controls,
                        )
                        .await);
                    }
                }
            }
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum AuthenticationOutcome {
    WaitingForInput,
    Authenticated,
}

async fn cancel_current(
    actor: &mut ActorState,
    expected_attempt: Option<&str>,
    expected_caller: Option<&str>,
    allow_after_cleanup: bool,
    emitter: Option<SignalEmitter<'static>>,
    snapshots: &watch::Sender<AuthSnapshot>,
    controls: &watch::Sender<Option<AttemptControl>>,
) -> fdo::Result<()> {
    // Invalidate resources before publishing Idle. Delayed disconnect or UI
    // cancellation commands are then harmless after cleanup completes.
    validate_cancel_target(&actor.auth, expected_attempt, allow_after_cleanup)?;
    if let Some(expected_caller) = expected_caller
        && actor.caller.as_deref() != Some(expected_caller)
    {
        return Ok(());
    }
    if !is_active_authentication_state(actor.auth.state())
        || actor.auth.state() == AuthState::Cancelling
    {
        return Ok(());
    }

    let attempt_id = actor
        .auth
        .active_attempt_id()
        .unwrap_or_default()
        .to_owned();
    actor
        .auth
        .transition(StateEvent::CancelRequested)
        .map_err(map_transition_error)?;
    publish_state(&actor.auth, &attempt_id, snapshots);
    if let Some(emitter) = emitter.as_ref() {
        emit_state_best_effort(Some(emitter), &snapshot(&actor.auth, &attempt_id)).await;
    }
    if let Some(token) = actor.cancellation.as_ref() {
        token.cancel();
    }
    if let Some(token) = actor.caller_watcher.as_ref() {
        token.cancel();
    }
    let cancel_result = if let Some(mut transport) = actor.transport.take() {
        match timeout(
            CANCEL_TIMEOUT,
            transport.cancel_session(&CancellationToken::new()),
        )
        .await
        {
            Ok(result) => result,
            Err(_) => Err(GreetdError::Timeout),
        }
    } else {
        Ok(GreetdResponse::Success)
    };
    actor.cancellation.take();
    actor.caller_watcher.take();
    actor.caller.take();
    let _ = controls.send(None);

    if actor.auth.state() == AuthState::Cancelling {
        actor
            .auth
            .transition(StateEvent::CancellationFinished)
            .map_err(map_transition_error)?;
        publish_state(&actor.auth, &attempt_id, snapshots);
        if let Some(emitter) = emitter.as_ref() {
            emit_state_best_effort(Some(emitter), &snapshot(&actor.auth, &attempt_id)).await;
        }
    }

    match cancel_result {
        Ok(GreetdResponse::Success) => Ok(()),
        Ok(GreetdResponse::Error {
            error_type,
            description,
        }) => Err(fdo::Error::Failed(format!(
            "could not cancel greetd session: {}",
            display_detail(&format!("{error_type}: {description}"))
        ))),
        Ok(GreetdResponse::AuthMessage { .. }) => Err(fdo::Error::Failed(
            "could not cancel greetd session: unexpected authentication message".to_owned(),
        )),
        Err(error) => Err(fdo::Error::Failed(format!(
            "could not cancel greetd session: {error}"
        ))),
    }
}

async fn finish_cancelled(
    actor: &mut ActorState,
    attempt_id: &str,
    emitter: Option<&SignalEmitter<'static>>,
    snapshots: &watch::Sender<AuthSnapshot>,
    controls: &watch::Sender<Option<AttemptControl>>,
) -> fdo::Error {
    if actor.auth.is_current_attempt(attempt_id) && actor.auth.state().is_active() {
        if let Err(error) = actor.auth.transition(StateEvent::CancelRequested) {
            tracing::warn!(%error, "could not enter cancellation state after transport cancellation");
        } else {
            publish_state(&actor.auth, attempt_id, snapshots);
            emit_state_best_effort(emitter, &snapshot(&actor.auth, attempt_id)).await;
        }
    }

    detach_resources(actor, controls);

    if actor.auth.state() == AuthState::Cancelling {
        if let Err(error) = actor.auth.transition(StateEvent::CancellationFinished) {
            tracing::warn!(%error, "could not finish cancellation after transport cancellation");
        } else {
            publish_state(&actor.auth, attempt_id, snapshots);
            emit_state_best_effort(emitter, &snapshot(&actor.auth, attempt_id)).await;
        }
    }

    cancelled_error()
}

async fn fail_transaction(
    actor: &mut ActorState,
    attempt_id: &str,
    error: GreetdError,
    emitter: &SignalEmitter<'static>,
    snapshots: &watch::Sender<AuthSnapshot>,
    controls: &watch::Sender<Option<AttemptControl>>,
) -> fdo::Error {
    if matches!(error, GreetdError::Cancelled) {
        return finish_cancelled(actor, attempt_id, Some(emitter), snapshots, controls).await;
    }
    let detail = display_detail(&error.to_string());
    if actor.auth.is_current_attempt(attempt_id) {
        let _ = actor.auth.transition(StateEvent::ProtocolFailure {
            detail: detail.clone(),
        });
        publish_state(&actor.auth, attempt_id, snapshots);
        emit_state_best_effort(Some(emitter), &snapshot(&actor.auth, attempt_id)).await;
        detach_resources(actor, controls);
    }
    fdo::Error::Failed(detail)
}

fn detach_resources(actor: &mut ActorState, controls: &watch::Sender<Option<AttemptControl>>) {
    // Dropping the transport closes the protocol session; cancelling both
    // tokens also stops the caller watcher and any pending greetd operation.
    actor.transport.take();
    if let Some(token) = actor.cancellation.take() {
        token.cancel();
    }
    if let Some(token) = actor.caller_watcher.take() {
        token.cancel();
    }
    actor.caller.take();
    let _ = controls.send(None);
}

async fn request_create_session(
    actor: &mut ActorState,
    username: &str,
    cancellation: &CancellationToken,
) -> Result<GreetdResponse, GreetdError> {
    actor
        .transport
        .as_mut()
        .ok_or_else(|| {
            GreetdError::UnexpectedResponse("greetd transport is unavailable".to_owned())
        })?
        .create_session(username, cancellation)
        .await
}

async fn request_post_response(
    actor: &mut ActorState,
    response: Option<&str>,
    cancellation: &CancellationToken,
) -> Result<GreetdResponse, GreetdError> {
    actor
        .transport
        .as_mut()
        .ok_or_else(|| {
            GreetdError::UnexpectedResponse("greetd transport is unavailable".to_owned())
        })?
        .post_auth_message_response(response, cancellation)
        .await
}

async fn request_start_session(
    actor: &mut ActorState,
    command: &[String],
    environment: &[String],
    cancellation: &CancellationToken,
) -> Result<GreetdResponse, GreetdError> {
    actor
        .transport
        .as_mut()
        .ok_or_else(|| {
            GreetdError::UnexpectedResponse("greetd transport is unavailable".to_owned())
        })?
        .start_session(command, environment, cancellation)
        .await
}

fn publish_state(
    auth: &AuthStateMachine,
    attempt_id: &str,
    snapshots: &watch::Sender<AuthSnapshot>,
) {
    let _ = snapshots.send(snapshot(auth, attempt_id));
}

fn snapshot(auth: &AuthStateMachine, attempt_id: &str) -> AuthSnapshot {
    AuthSnapshot::from_auth(auth, attempt_id)
}

fn spawn_caller_watcher(
    connection: zbus::Connection,
    caller: String,
    attempt_id: String,
    watcher_token: CancellationToken,
    cancellation: CancellationToken,
    commands: CommandSender,
) {
    // D-Bus may remove the caller while the original request is blocked in
    // greetd, so this watcher must outlive the initiating method call.
    tokio::spawn(async move {
        let proxy = match zbus::fdo::DBusProxy::new(&connection).await {
            Ok(proxy) => proxy,
            Err(error) => {
                tracing::warn!(%error, "could not create D-Bus disconnect watcher");
                request_caller_cancel(commands, attempt_id, caller, cancellation).await;
                return;
            }
        };
        let mut stream = match proxy
            .receive_name_owner_changed_with_args(&[(0, caller.as_str()), (2, "")])
            .await
        {
            Ok(stream) => stream,
            Err(error) => {
                tracing::warn!(%error, "could not subscribe to D-Bus client disconnects");
                request_caller_cancel(commands, attempt_id, caller, cancellation).await;
                return;
            }
        };
        let caller_name = match caller.as_str().try_into() {
            Ok(name) => name,
            Err(error) => {
                tracing::warn!(%error, "D-Bus caller name was invalid");
                return;
            }
        };
        if !proxy.name_has_owner(caller_name).await.unwrap_or(false) {
            request_caller_cancel(commands, attempt_id, caller, cancellation).await;
            return;
        }
        tokio::select! {
            _ = watcher_token.cancelled() => {}
            _ = stream.next() => request_caller_cancel(commands, attempt_id, caller, cancellation).await,
        }
    });
}

async fn request_caller_cancel(
    commands: CommandSender,
    attempt_id: String,
    caller: String,
    cancellation: CancellationToken,
) {
    cancellation.cancel();
    let (reply, receiver) = oneshot::channel();
    if commands
        .send(AuthCommand::Cancel {
            expected_attempt: Some(attempt_id),
            expected_caller: Some(caller),
            allow_after_cleanup: false,
            emitter: None,
            reply,
        })
        .await
        .is_ok()
    {
        let _ = receiver.await;
    }
}

fn schedule_handoff_after_reply(connection: zbus::Connection, handoff: Arc<Notify>) {
    let activity = connection.monitor_activity();
    tokio::spawn(async move {
        activity.await;
        handoff.notify_waiters();
    });
}

async fn emit_state_best_effort(emitter: Option<&SignalEmitter<'_>>, snapshot: &AuthSnapshot) {
    let Some(emitter) = emitter else {
        return;
    };
    if let Err(error) = crate::dbus_service::GreeterService::state_changed(
        emitter,
        snapshot.attempt_id.clone(),
        snapshot.state.clone(),
        snapshot.detail.clone(),
    )
    .await
    {
        tracing::debug!(%error, state = %snapshot.state, "could not emit StateChanged");
    }
}

async fn emit_prompt_best_effort(
    emitter: &SignalEmitter<'_>,
    attempt_id: &str,
    prompt_kind: &str,
    text: String,
) {
    if let Err(error) = crate::dbus_service::GreeterService::prompt(
        emitter,
        attempt_id.to_owned(),
        prompt_kind.to_owned(),
        text,
    )
    .await
    {
        tracing::debug!(%error, "could not emit Prompt");
    }
}

fn validate_attempt(auth: &AuthStateMachine, attempt_id: &str) -> fdo::Result<()> {
    if auth.is_current_attempt(attempt_id) {
        Ok(())
    } else {
        Err(fdo::Error::Failed("stale or unknown attempt id".to_owned()))
    }
}

fn validate_cancel_target(
    auth: &AuthStateMachine,
    expected_attempt: Option<&str>,
    allow_after_cleanup: bool,
) -> fdo::Result<()> {
    if let Some(expected_attempt) = expected_attempt
        && !auth.is_current_attempt(expected_attempt)
    {
        if allow_after_cleanup && auth.state() == AuthState::Idle {
            return Ok(());
        }
        return Err(fdo::Error::Failed("stale or unknown attempt id".to_owned()));
    }
    Ok(())
}

fn require_state(auth: &AuthStateMachine, expected: AuthState) -> fdo::Result<()> {
    if auth.state() == expected {
        Ok(())
    } else {
        Err(fdo::Error::Failed(format!(
            "operation is not valid in state {}",
            auth.state().as_str()
        )))
    }
}

fn is_active_authentication_state(state: AuthState) -> bool {
    matches!(
        state,
        AuthState::CreatingSession
            | AuthState::PromptPending
            | AuthState::WaitingForInput
            | AuthState::SubmittingResponse
            | AuthState::Authenticated
            | AuthState::ResolvingSession
            | AuthState::StartingSession
            | AuthState::Cancelling
    )
}

fn session_environment(session: &SessionEntry) -> Vec<String> {
    // The backend owns the launch environment and does not inherit a caller's
    // PATH when executing a desktop entry selected through D-Bus.
    let mut environment = vec![
        "PATH=/usr/local/bin:/usr/bin:/bin".to_owned(),
        format!("XDG_SESSION_TYPE={}", session.session_type.as_str()),
    ];
    if let Some(desktop_name) = session.desktop_names.first() {
        environment.push(format!("XDG_SESSION_DESKTOP={desktop_name}"));
        environment.push(format!(
            "XDG_CURRENT_DESKTOP={}",
            session.desktop_names.join(":")
        ));
    }
    environment
}

fn display_detail(detail: &str) -> String {
    // Error text crosses the D-Bus boundary, so remove control characters and
    // cap its size before retaining or displaying it.
    detail
        .chars()
        .filter(|character| !character.is_control() || *character == '\n' || *character == '\t')
        .take(512)
        .collect()
}

fn cancelled_error() -> fdo::Error {
    fdo::Error::Failed("authentication attempt was cancelled".to_owned())
}

fn map_begin_authentication_error(error: BeginAuthenticationError) -> fdo::Error {
    let detail = error.to_string();
    match error {
        BeginAuthenticationError::EmptyUsername => fdo::Error::InvalidArgs(detail),
        BeginAuthenticationError::InvalidState(_)
        | BeginAuthenticationError::AttemptIdExhausted => fdo::Error::Failed(detail),
    }
}

fn map_transition_error(error: crate::state::StateTransitionError) -> fdo::Error {
    fdo::Error::Failed(error.to_string())
}

#[cfg(test)]
mod tests {
    use tokio::sync::watch;

    use super::{ActorState, AuthSnapshot, cancel_current, validate_cancel_target};
    use crate::state::{AuthState, AuthStateMachine, StateEvent};

    fn cancelled_attempt() -> (AuthStateMachine, String) {
        let mut auth = AuthStateMachine::default();
        let attempt_id = auth.begin_authentication("alice".to_owned()).unwrap();
        auth.transition(StateEvent::CancelRequested).unwrap();
        auth.transition(StateEvent::CancellationFinished).unwrap();
        (auth, attempt_id)
    }

    #[test]
    fn disconnect_cancel_cannot_cross_cleanup_boundary() {
        let (auth, attempt_id) = cancelled_attempt();

        assert_eq!(auth.state(), AuthState::Idle);
        assert!(validate_cancel_target(&auth, Some(&attempt_id), false).is_err());
    }

    #[test]
    fn explicit_cancel_is_idempotent_when_cleanup_wins_the_race() {
        let (auth, attempt_id) = cancelled_attempt();

        assert!(validate_cancel_target(&auth, Some(&attempt_id), true).is_ok());
    }

    #[tokio::test]
    async fn explicit_cancel_after_cleanup_does_not_mutate_idle_state() {
        let mut actor = ActorState::default();
        let attempt_id = actor.auth.begin_authentication("alice".to_owned()).unwrap();
        let (snapshots, _) = watch::channel(AuthSnapshot::idle());
        let (controls, _) = watch::channel(None);

        cancel_current(
            &mut actor,
            Some(&attempt_id),
            None,
            false,
            None,
            &snapshots,
            &controls,
        )
        .await
        .unwrap();

        cancel_current(
            &mut actor,
            Some(&attempt_id),
            None,
            true,
            None,
            &snapshots,
            &controls,
        )
        .await
        .unwrap();
        assert_eq!(actor.auth.state(), AuthState::Idle);
    }
}
