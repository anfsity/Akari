//! Owns an active attempt, greetd I/O, cleanup, and ordered state/prompt signals.
//!
//! The actor calls these operations serially. Attempt resources are detached
//! before publishing Idle, and interrupted framing always drops its transport.

use std::time::Duration;

use tokio::{
    sync::{mpsc, watch},
    time::timeout,
};
use tokio_util::sync::CancellationToken;
use zbus::{fdo, object_server::SignalEmitter};

use super::{caller_watch::spawn_caller_watcher, handle::AuthCommand};
use crate::{
    greetd::{GreetdError, GreetdResponse, GreetdTransport},
    session_catalog::SessionEntry,
    session_launch::get_session_launch,
    state::{AuthState, AuthStateMachine, StateEvent},
};

const CANCEL_TIMEOUT: Duration = Duration::from_secs(1);

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct AuthSnapshot {
    pub(super) attempt_id: String,
    pub(super) state: String,
    pub(super) detail: String,
}

impl AuthSnapshot {
    pub(super) fn idle() -> Self {
        Self {
            attempt_id: String::new(),
            state: AuthState::Idle.as_str().to_owned(),
            detail: String::new(),
        }
    }

    pub(super) fn from_auth(auth: &AuthStateMachine, attempt_id: &str) -> Self {
        Self {
            attempt_id: attempt_id.to_owned(),
            state: auth.get_state().as_str().to_owned(),
            detail: auth.get_detail().to_owned(),
        }
    }
}

#[derive(Clone, Debug)]
pub(super) struct AttemptControl {
    pub(super) caller: String,
    pub(super) attempt_id: String,
    pub(super) cancellation: CancellationToken,
}

/// Mutable authentication resources owned exclusively by `run_actor`.
pub(super) struct ActorState {
    pub(super) auth: AuthStateMachine,
    attempt: Option<AttemptResources>,
    snapshots: watch::Sender<AuthSnapshot>,
    controls: watch::Sender<Option<AttemptControl>>,
    shutdown: CancellationToken,
}

/// Caller and cancellation resources exist together throughout an active attempt.
/// Transport is absent only while connecting or reconnecting after rejection.
struct AttemptResources {
    caller: String,
    cancellation: CancellationToken,
    caller_watcher: CancellationToken,
    transport: Option<GreetdTransport>,
    user_response_submitted: bool,
}

impl Drop for AttemptResources {
    fn drop(&mut self) {
        self.cancellation.cancel();
        self.caller_watcher.cancel();
    }
}

impl ActorState {
    pub(super) fn new(
        snapshots: watch::Sender<AuthSnapshot>,
        controls: watch::Sender<Option<AttemptControl>>,
        shutdown: CancellationToken,
    ) -> Self {
        Self {
            auth: AuthStateMachine::default(),
            attempt: None,
            snapshots,
            controls,
            shutdown,
        }
    }

    fn get_attempt(&self) -> &AttemptResources {
        self.attempt
            .as_ref()
            .expect("active authentication owns attempt resources")
    }

    fn transport_mut(&mut self) -> &mut GreetdTransport {
        self.attempt
            .as_mut()
            .expect("active authentication owns attempt resources")
            .transport
            .as_mut()
            .expect("connected authentication owns greetd transport")
    }

    fn detach_resources(&mut self) {
        self.attempt.take();
        let _ = self.controls.send(None);
    }

    async fn publish_snapshot(&self, attempt_id: &str, emitter: Option<&SignalEmitter<'_>>) {
        let snapshot = AuthSnapshot::from_auth(&self.auth, attempt_id);
        tracing::info!(%attempt_id, state = %snapshot.state, "authentication state changed");
        let _ = self.snapshots.send(snapshot.clone());
        emit_state_best_effort(emitter, snapshot).await;
    }

    async fn apply_transition(
        &mut self,
        attempt_id: &str,
        event: StateEvent,
        emitter: Option<&SignalEmitter<'_>>,
    ) {
        self.auth
            .transition(sanitize_event_detail(event))
            .expect("authentication event matches the actor phase");
        self.publish_snapshot(attempt_id, emitter).await;
    }
}

#[derive(Clone, Copy)]
enum PromptDisposition {
    NeedsInput,
    AutoAcknowledge,
}

pub(super) async fn create_attempt(
    actor: &mut ActorState,
    caller: String,
    username: String,
    emitter: &SignalEmitter<'static>,
    commands: &mpsc::WeakSender<AuthCommand>,
) -> fdo::Result<String> {
    if actor
        .attempt
        .as_ref()
        .is_some_and(|attempt| attempt.caller != caller)
    {
        return Err(fdo::Error::AccessDenied(
            "authentication belongs to another D-Bus caller".to_owned(),
        ));
    }
    if let Err(error) = cancel_current(actor, None, None, false, None).await {
        tracing::warn!(
            %caller,
            %error,
            "previous attempt transport cancellation failed during replacement"
        );
    }
    debug_assert_eq!(actor.auth.get_state(), AuthState::Idle);

    let cancellation = actor.shutdown.child_token();
    let watcher_token = CancellationToken::new();
    let attempt_id = actor
        .auth
        .begin_authentication(username)
        .map_err(|error| fdo::Error::Failed(error.to_string()))?;
    tracing::Span::current().record("attempt_id", &attempt_id);
    actor.attempt = Some(AttemptResources {
        caller: caller.clone(),
        cancellation: cancellation.clone(),
        caller_watcher: watcher_token.clone(),
        transport: None,
        user_response_submitted: false,
    });
    tracing::info!(%attempt_id, %caller, state = actor.auth.get_state().as_str(), "authentication started");
    let _ = actor.controls.send(Some(AttemptControl {
        caller: caller.clone(),
        attempt_id: attempt_id.clone(),
        cancellation: cancellation.clone(),
    }));
    actor.publish_snapshot(&attempt_id, Some(emitter)).await;
    spawn_caller_watcher(
        emitter.connection().clone(),
        caller,
        attempt_id.clone(),
        watcher_token,
        cancellation,
        commands.clone(),
    );

    Ok(attempt_id)
}

pub(super) async fn run_authentication(
    actor: &mut ActorState,
    attempt_id: &str,
    username: &str,
    emitter: SignalEmitter<'static>,
) -> fdo::Result<()> {
    let cancellation = actor.get_attempt().cancellation.clone();
    // I/O stays in the same actor command after acceptance, so cancellation
    // still finishes cleanup before a replacement transaction can start.
    let result = GreetdTransport::connect(&cancellation).await;
    let transport = handle_transport_result(actor, attempt_id, result, &emitter).await?;
    actor
        .attempt
        .as_mut()
        .expect("active authentication owns attempt resources")
        .transport = Some(transport);

    let response = actor
        .transport_mut()
        .create_session(username, &cancellation)
        .await;
    let response = handle_transport_result(actor, attempt_id, response, &emitter).await?;

    consume_response(actor, attempt_id, response, emitter, &cancellation).await
}

pub(super) async fn handle_respond(
    actor: &mut ActorState,
    attempt_id: &str,
    response: zeroize::Zeroizing<String>,
    emitter: SignalEmitter<'static>,
) -> fdo::Result<()> {
    validate_state(&actor.auth, AuthState::WaitingForInput)?;
    let cancellation = actor.get_attempt().cancellation.clone();

    actor
        .attempt
        .as_mut()
        .expect("active authentication owns attempt resources")
        .user_response_submitted = true;

    actor
        .apply_transition(attempt_id, StateEvent::ResponseSubmitted, Some(&emitter))
        .await;

    let result = actor
        .transport_mut()
        .post_auth_message_response(Some(response.as_str()), &cancellation)
        .await;
    drop(response);
    let next_response = handle_transport_result(actor, attempt_id, result, &emitter).await?;

    consume_response(actor, attempt_id, next_response, emitter, &cancellation).await
}

pub(super) async fn begin_session_resolution(
    actor: &mut ActorState,
    attempt_id: &str,
    emitter: &SignalEmitter<'static>,
) -> fdo::Result<()> {
    validate_state(&actor.auth, AuthState::Authenticated)?;
    actor
        .apply_transition(attempt_id, StateEvent::StartSessionRequested, Some(emitter))
        .await;
    Ok(())
}

pub(super) async fn report_session_unavailable(
    actor: &mut ActorState,
    attempt_id: &str,
    detail: String,
    emitter: &SignalEmitter<'static>,
) -> fdo::Result<()> {
    validate_state(&actor.auth, AuthState::ResolvingSession)?;
    actor
        .apply_transition(
            attempt_id,
            StateEvent::SessionUnavailable { detail },
            Some(emitter),
        )
        .await;
    Ok(())
}

pub(super) async fn fail_session_resolution(
    actor: &mut ActorState,
    attempt_id: &str,
    detail: String,
    emitter: &SignalEmitter<'static>,
) -> fdo::Result<()> {
    validate_state(&actor.auth, AuthState::ResolvingSession)?;
    actor
        .apply_transition(
            attempt_id,
            StateEvent::ProtocolFailure { detail },
            Some(emitter),
        )
        .await;
    actor.detach_resources();
    Ok(())
}

pub(super) async fn handle_start_session(
    actor: &mut ActorState,
    attempt_id: &str,
    session: SessionEntry,
    emitter: SignalEmitter<'static>,
) -> fdo::Result<()> {
    validate_state(&actor.auth, AuthState::ResolvingSession)?;
    let (command, environment) = match get_session_launch(&session) {
        Ok(launch) => launch,
        Err(error) => {
            let detail =
                sanitize_detail(&format!("could not prepare user session launcher: {error}"));
            tracing::error!(%attempt_id, error = ?error, "user session launcher preparation failed");
            fail_session_resolution(actor, attempt_id, detail.clone(), &emitter).await?;
            return Err(fdo::Error::Failed(detail));
        }
    };
    let cancellation = actor.get_attempt().cancellation.clone();

    actor
        .apply_transition(attempt_id, StateEvent::SessionResolved, Some(&emitter))
        .await;

    tracing::info!(%attempt_id, session_id = %session.session_id, source = %session.source.display(), state = actor.auth.get_state().as_str(), "starting desktop session");
    let response = actor
        .transport_mut()
        .start_session(&command, &environment, &cancellation)
        .await;
    let response = handle_transport_result(actor, attempt_id, response, &emitter).await?;

    match response {
        GreetdResponse::Success => {
            tracing::info!(%attempt_id, session_id = %session.session_id, "desktop session accepted by greetd");
            actor
                .apply_transition(attempt_id, StateEvent::SessionStarted, Some(&emitter))
                .await;
            actor.detach_resources();
            Ok(())
        }
        GreetdResponse::Error {
            error_type,
            description,
        } => {
            tracing::error!(%attempt_id, %error_type, state = actor.auth.get_state().as_str(), "desktop session start failed");
            let detail = sanitize_detail(&format!("{error_type}: {description}"));
            actor
                .apply_transition(
                    attempt_id,
                    StateEvent::SessionStartFailed {
                        detail: detail.clone(),
                    },
                    Some(&emitter),
                )
                .await;
            actor.detach_resources();
            Err(fdo::Error::Failed(detail))
        }
        GreetdResponse::AuthMessage { .. } => Err(fail_transaction(
            actor,
            attempt_id,
            GreetdError::UnexpectedResponse(
                "greetd returned an authentication message while starting a session".to_owned(),
            ),
            &emitter,
        )
        .await),
    }
}

/// Transport failures always complete actor cleanup before returning to the
/// command loop. Connection and frame exchanges use the same cancellation and
/// failure transitions, so callers cannot accidentally leave an attempt alive.
async fn handle_transport_result<T>(
    actor: &mut ActorState,
    attempt_id: &str,
    result: Result<T, GreetdError>,
    emitter: &SignalEmitter<'static>,
) -> fdo::Result<T> {
    match result {
        Ok(value) => Ok(value),
        Err(GreetdError::Cancelled) => {
            Err(finish_cancellation(actor, attempt_id, Some(emitter)).await)
        }
        Err(error) => Err(fail_transaction(actor, attempt_id, error, emitter).await),
    }
}

async fn consume_response(
    actor: &mut ActorState,
    attempt_id: &str,
    mut response: GreetdResponse,
    emitter: SignalEmitter<'static>,
    cancellation: &CancellationToken,
) -> fdo::Result<()> {
    // One greetd response can require several follow-up frames: visible and
    // secret prompts wait for the UI, while informational messages are
    // acknowledged automatically and continue the same transaction.
    loop {
        if cancellation.is_cancelled() {
            return Err(finish_cancellation(actor, attempt_id, Some(&emitter)).await);
        }
        match response {
            GreetdResponse::Success => {
                tracing::info!(%attempt_id, state = actor.auth.get_state().as_str(), "authentication succeeded");
                actor
                    .apply_transition(
                        attempt_id,
                        StateEvent::AuthenticationSucceeded,
                        Some(&emitter),
                    )
                    .await;
                return Ok(());
            }
            GreetdResponse::Error {
                error_type,
                description,
            } => {
                let detail = sanitize_detail(&format!("{error_type}: {description}"));
                // greetd 0.10 retains its configuring slot after PAM failure.
                // Cancel removes that slot before contacting the dead worker,
                // so even its Error response completes server-side cleanup.
                // Transport failures and unexpected prompts remain failures.
                let result = actor.transport_mut().cancel_session(cancellation).await;
                let cancel_response =
                    handle_transport_result(actor, attempt_id, result, &emitter).await?;
                if matches!(cancel_response, GreetdResponse::AuthMessage { .. }) {
                    return Err(fail_transaction(
                        actor,
                        attempt_id,
                        GreetdError::UnexpectedResponse(
                            "unexpected prompt while cancelling rejected authentication".to_owned(),
                        ),
                        &emitter,
                    )
                    .await);
                }
                // Automatic info/error acknowledgments also use
                // SubmittingResponse. Only a conversation with user input may
                // restart on rejection; otherwise PAM failures can loop and
                // consume login attempts without anyone submitting a response.
                if error_type == "auth_error" && actor.get_attempt().user_response_submitted {
                    tracing::info!(%attempt_id, %error_type, state = actor.auth.get_state().as_str(), "credential rejected; retrying authentication");
                    let username = actor
                        .auth
                        .find_active_username()
                        .expect("active authentication owns a username")
                        .to_owned();
                    actor
                        .apply_transition(
                            attempt_id,
                            StateEvent::CredentialRejected {
                                detail: detail.clone(),
                            },
                            Some(&emitter),
                        )
                        .await;
                    emit_prompt_best_effort(&emitter, attempt_id, "error", detail, cancellation)
                        .await;

                    let resources = actor
                        .attempt
                        .as_mut()
                        .expect("active authentication owns attempt resources");
                    resources.transport.take();
                    resources.user_response_submitted = false;

                    let result = GreetdTransport::connect(cancellation).await;
                    let transport =
                        handle_transport_result(actor, attempt_id, result, &emitter).await?;
                    actor
                        .attempt
                        .as_mut()
                        .expect("active authentication owns attempt resources")
                        .transport = Some(transport);
                    let result = actor
                        .transport_mut()
                        .create_session(&username, cancellation)
                        .await;
                    response = handle_transport_result(actor, attempt_id, result, &emitter).await?;
                    continue;
                }

                tracing::warn!(%attempt_id, %error_type, state = actor.auth.get_state().as_str(), "authentication rejected by greetd");
                actor
                    .apply_transition(
                        attempt_id,
                        StateEvent::AuthenticationFailed {
                            detail: detail.clone(),
                        },
                        Some(&emitter),
                    )
                    .await;
                actor.detach_resources();
                return Err(fdo::Error::Failed(detail));
            }
            GreetdResponse::AuthMessage {
                auth_message_type,
                auth_message,
            } => {
                let disposition = match auth_message_type.as_str() {
                    "visible" | "secret" => PromptDisposition::NeedsInput,
                    "info" | "error" => PromptDisposition::AutoAcknowledge,
                    _ => {
                        return Err(fail_transaction(
                            actor,
                            attempt_id,
                            GreetdError::UnexpectedResponse(format!(
                                "unsupported authentication message type: {auth_message_type}"
                            )),
                            &emitter,
                        )
                        .await);
                    }
                };
                actor
                    .apply_transition(attempt_id, StateEvent::AuthMessage, Some(&emitter))
                    .await;
                if cancellation.is_cancelled() {
                    return Err(finish_cancellation(actor, attempt_id, Some(&emitter)).await);
                }
                emit_prompt_best_effort(
                    &emitter,
                    attempt_id,
                    &auth_message_type,
                    auth_message,
                    cancellation,
                )
                .await;
                if cancellation.is_cancelled() {
                    return Err(finish_cancellation(actor, attempt_id, Some(&emitter)).await);
                }
                match disposition {
                    PromptDisposition::NeedsInput => {
                        actor
                            .apply_transition(
                                attempt_id,
                                StateEvent::PromptNeedsInput,
                                Some(&emitter),
                            )
                            .await;
                        if cancellation.is_cancelled() {
                            return Err(
                                finish_cancellation(actor, attempt_id, Some(&emitter)).await
                            );
                        }
                        return Ok(());
                    }
                    PromptDisposition::AutoAcknowledge => {
                        actor
                            .apply_transition(
                                attempt_id,
                                StateEvent::PromptAutoResponse,
                                Some(&emitter),
                            )
                            .await;
                        let result = actor
                            .transport_mut()
                            .post_auth_message_response(None, cancellation)
                            .await;
                        response =
                            handle_transport_result(actor, attempt_id, result, &emitter).await?;
                    }
                }
            }
        }
    }
}

pub(super) async fn cancel_current(
    actor: &mut ActorState,
    expected_attempt: Option<&str>,
    expected_caller: Option<&str>,
    allow_after_cleanup: bool,
    emitter: Option<SignalEmitter<'static>>,
) -> fdo::Result<()> {
    // Invalidate resources before publishing Idle. Delayed disconnect or UI
    // cancellation commands are then harmless after cleanup completes.
    validate_cancel_request(
        actor,
        expected_attempt,
        expected_caller,
        allow_after_cleanup,
    )?;
    if !actor.auth.get_state().is_active() {
        return Ok(());
    }

    let attempt_id = actor
        .auth
        .find_active_attempt_id()
        .expect("active authentication owns an attempt ID")
        .to_owned();
    tracing::info!(%attempt_id, state = actor.auth.get_state().as_str(), "cancelling authentication");
    actor
        .apply_transition(&attempt_id, StateEvent::CancelRequested, emitter.as_ref())
        .await;
    let mut resources = actor
        .attempt
        .take()
        .expect("active authentication owns attempt resources");
    resources.cancellation.cancel();
    resources.caller_watcher.cancel();
    let _ = actor.controls.send(None);
    let cancel_result = if let Some(mut transport) = resources.transport.take() {
        // The attempt token is already cancelled. A fresh token permits a
        // bounded graceful cancel exchange before the socket is dropped.
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
    actor
        .apply_transition(
            &attempt_id,
            StateEvent::CancellationFinished,
            emitter.as_ref(),
        )
        .await;

    match cancel_result {
        Ok(GreetdResponse::Success) => {
            tracing::info!(%attempt_id, "authentication cancelled");
            Ok(())
        }
        Ok(GreetdResponse::Error {
            error_type,
            description,
        }) => {
            tracing::warn!(%attempt_id, %error_type, "greetd rejected cancellation; transport closed");
            Err(fdo::Error::Failed(format!(
                "could not cancel greetd session: {}",
                sanitize_detail(&format!("{error_type}: {description}"))
            )))
        }
        Ok(GreetdResponse::AuthMessage { .. }) => {
            tracing::warn!(%attempt_id, "unexpected authentication message during cancellation; transport closed");
            Err(fdo::Error::Failed(
                "could not cancel greetd session: unexpected authentication message".to_owned(),
            ))
        }
        Err(error) => {
            tracing::warn!(%attempt_id, error = ?error, state = actor.auth.get_state().as_str(), "greetd cancellation failed; transport closed");
            Err(fdo::Error::Failed(format!(
                "could not cancel greetd session: {error}"
            )))
        }
    }
}

pub(super) async fn finish_cancellation(
    actor: &mut ActorState,
    attempt_id: &str,
    emitter: Option<&SignalEmitter<'static>>,
) -> fdo::Error {
    // Interrupted framing may leave unread response bytes or a partial request.
    // Close this transport instead of sending another request over a socket
    // whose next frame boundary is no longer known.
    assert!(
        actor.auth.is_current_attempt(attempt_id),
        "actor cancels its current attempt"
    );
    tracing::info!(%attempt_id, state = actor.auth.get_state().as_str(), "cancelling authentication");
    actor
        .apply_transition(attempt_id, StateEvent::CancelRequested, emitter)
        .await;
    actor.detach_resources();
    actor
        .apply_transition(attempt_id, StateEvent::CancellationFinished, emitter)
        .await;

    tracing::info!(%attempt_id, "authentication cancelled; transport closed");
    fdo::Error::Failed("authentication attempt was cancelled".to_owned())
}

async fn fail_transaction(
    actor: &mut ActorState,
    attempt_id: &str,
    error: GreetdError,
    emitter: &SignalEmitter<'static>,
) -> fdo::Error {
    tracing::error!(%attempt_id, error = ?error, state = actor.auth.get_state().as_str(), "authentication transaction failed");
    let detail = sanitize_detail(&error.to_string());
    assert!(
        actor.auth.is_current_attempt(attempt_id),
        "actor fails its current attempt"
    );
    actor
        .apply_transition(
            attempt_id,
            StateEvent::ProtocolFailure {
                detail: detail.clone(),
            },
            Some(emitter),
        )
        .await;
    actor.detach_resources();
    fdo::Error::Failed(detail)
}

async fn emit_state_best_effort(emitter: Option<&SignalEmitter<'_>>, snapshot: AuthSnapshot) {
    let Some(emitter) = emitter else {
        return;
    };
    let attempt_id = snapshot.attempt_id;
    let state = snapshot.state;
    if let Err(error) = crate::service::GreeterService::state_changed(
        emitter,
        attempt_id.clone(),
        state.clone(),
        snapshot.detail,
    )
    .await
    {
        if emitter.connection().is_closed() {
            tracing::debug!(%attempt_id, %state, %error, "StateChanged skipped on closed bus");
        } else {
            tracing::warn!(%attempt_id, %state, %error, "could not emit StateChanged");
        }
    }
}

async fn emit_prompt_best_effort(
    emitter: &SignalEmitter<'_>,
    attempt_id: &str,
    prompt_kind: &str,
    text: String,
    cancellation: &CancellationToken,
) {
    if let Err(error) = crate::service::GreeterService::prompt(
        emitter,
        attempt_id.to_owned(),
        prompt_kind.to_owned(),
        sanitize_detail(&text),
    )
    .await
    {
        if cancellation.is_cancelled() || emitter.connection().is_closed() {
            tracing::debug!(%attempt_id, %prompt_kind, %error, "Prompt delivery interrupted by disconnect or cancellation");
        } else {
            tracing::warn!(%attempt_id, %prompt_kind, %error, "could not emit authentication Prompt");
        }
    }
}

pub(super) fn validate_owned_attempt(
    actor: &ActorState,
    attempt_id: &str,
    caller: &str,
) -> fdo::Result<()> {
    if !actor.auth.is_current_attempt(attempt_id) {
        return Err(fdo::Error::Failed("stale or unknown attempt id".to_owned()));
    }
    if actor.get_attempt().caller != caller {
        return Err(fdo::Error::AccessDenied(
            "authentication belongs to another D-Bus caller".to_owned(),
        ));
    }
    Ok(())
}

fn validate_cancel_request(
    actor: &ActorState,
    expected_attempt: Option<&str>,
    expected_caller: Option<&str>,
    allow_after_cleanup: bool,
) -> fdo::Result<()> {
    // An explicit Cancel that already interrupted its owned token may arrive
    // after I/O cleanup returned to Idle. Only that acknowledged interruption
    // permits success here; a delayed watcher must still reject a stale target.
    if allow_after_cleanup && actor.auth.get_state() == AuthState::Idle {
        return Ok(());
    }
    if let Some(expected_attempt) = expected_attempt
        && !actor.auth.is_current_attempt(expected_attempt)
    {
        return Err(fdo::Error::Failed("stale or unknown attempt id".to_owned()));
    }
    if let Some(expected_caller) = expected_caller
        && actor
            .attempt
            .as_ref()
            .is_none_or(|attempt| attempt.caller != expected_caller)
    {
        return Err(fdo::Error::AccessDenied(
            "authentication belongs to another D-Bus caller".to_owned(),
        ));
    }
    Ok(())
}

fn validate_state(auth: &AuthStateMachine, expected: AuthState) -> fdo::Result<()> {
    if auth.get_state() == expected {
        Ok(())
    } else {
        Err(fdo::Error::Failed(format!(
            "operation is not valid in state {}",
            auth.get_state().as_str()
        )))
    }
}

fn sanitize_event_detail(event: StateEvent) -> StateEvent {
    match event {
        StateEvent::AuthenticationFailed { detail } => StateEvent::AuthenticationFailed {
            detail: sanitize_detail(&detail),
        },
        StateEvent::CredentialRejected { detail } => StateEvent::CredentialRejected {
            detail: sanitize_detail(&detail),
        },
        StateEvent::SessionUnavailable { detail } => StateEvent::SessionUnavailable {
            detail: sanitize_detail(&detail),
        },
        StateEvent::SessionStartFailed { detail } => StateEvent::SessionStartFailed {
            detail: sanitize_detail(&detail),
        },
        StateEvent::ProtocolFailure { detail } => StateEvent::ProtocolFailure {
            detail: sanitize_detail(&detail),
        },
        other => other,
    }
}

pub(crate) fn sanitize_detail(detail: &str) -> String {
    // Error text crosses the D-Bus boundary, so remove control characters and
    // cap its size before retaining or displaying it.
    detail
        .chars()
        .filter(|character| !character.is_control() || *character == '\n' || *character == '\t')
        .take(512)
        .collect()
}

#[cfg(test)]
mod tests {
    use tokio::sync::watch;
    use tokio_util::sync::CancellationToken;

    use super::{
        ActorState, AttemptResources, AuthSnapshot, cancel_current, sanitize_detail,
        sanitize_event_detail, validate_cancel_request, validate_owned_attempt,
    };
    use crate::state::{AuthState, AuthStateMachine, StateEvent};

    fn test_actor() -> ActorState {
        let (snapshots, _) = watch::channel(AuthSnapshot::idle());
        let (controls, _) = watch::channel(None);
        ActorState::new(snapshots, controls, CancellationToken::new())
    }

    fn cancelled_actor() -> (ActorState, String) {
        let mut actor = test_actor();
        let attempt_id = actor.auth.begin_authentication("alice".to_owned()).unwrap();
        actor.auth.transition(StateEvent::CancelRequested).unwrap();
        actor
            .auth
            .transition(StateEvent::CancellationFinished)
            .unwrap();
        (actor, attempt_id)
    }

    #[test]
    fn disconnect_cancel_stops_at_cleanup() {
        let (actor, attempt_id) = cancelled_actor();

        assert_eq!(actor.auth.get_state(), AuthState::Idle);
        assert!(validate_cancel_request(&actor, Some(&attempt_id), Some(":1.1"), false).is_err());
    }

    #[test]
    fn cancel_is_idempotent_after_cleanup() {
        let (actor, attempt_id) = cancelled_actor();

        assert!(validate_cancel_request(&actor, Some(&attempt_id), Some(":1.1"), true).is_ok());
    }

    #[test]
    fn validates_owned_current_attempt() {
        let mut actor = test_actor();
        let attempt_id = actor.auth.begin_authentication("alice".to_owned()).unwrap();
        actor.attempt = Some(AttemptResources {
            caller: ":1.1".to_owned(),
            cancellation: CancellationToken::new(),
            caller_watcher: CancellationToken::new(),
            transport: None,
            user_response_submitted: false,
        });

        assert!(validate_owned_attempt(&actor, &attempt_id, ":1.1").is_ok());
        assert!(validate_owned_attempt(&actor, &attempt_id, ":1.2").is_err());
        assert!(validate_owned_attempt(&actor, "attempt-stale", ":1.1").is_err());
    }

    #[test]
    fn snapshot_has_state_and_detail() {
        let mut auth = AuthStateMachine::default();
        let attempt_id = auth.begin_authentication("alice".to_owned()).unwrap();
        auth.transition(StateEvent::AuthenticationFailed {
            detail: "bad password".to_owned(),
        })
        .unwrap();

        assert_eq!(
            AuthSnapshot::from_auth(&auth, &attempt_id),
            AuthSnapshot {
                attempt_id,
                state: "Failed".to_owned(),
                detail: "bad password".to_owned(),
            }
        );
    }

    #[test]
    fn sanitizes_detail_and_session_unavailable_events() {
        let detail = format!("before\r\u{0}\nafter{}", "x".repeat(600));
        let sanitized = sanitize_detail(&detail);

        assert!(!sanitized.contains('\r'));
        assert!(!sanitized.contains('\0'));
        assert!(sanitized.contains("before\nafter"));
        assert_eq!(sanitized.chars().count(), 512);

        let StateEvent::SessionUnavailable {
            detail: event_detail,
        } = sanitize_event_detail(StateEvent::SessionUnavailable { detail })
        else {
            panic!("expected SessionUnavailable");
        };
        assert_eq!(event_detail, sanitized);
    }

    #[tokio::test]
    async fn cancel_after_cleanup_keeps_idle() {
        let mut actor = test_actor();
        let attempt_id = actor.auth.begin_authentication("alice".to_owned()).unwrap();
        actor.attempt = Some(AttemptResources {
            caller: ":1.1".to_owned(),
            cancellation: CancellationToken::new(),
            caller_watcher: CancellationToken::new(),
            transport: None,
            user_response_submitted: false,
        });

        cancel_current(&mut actor, Some(&attempt_id), None, false, None)
            .await
            .unwrap();

        cancel_current(&mut actor, Some(&attempt_id), Some(":1.1"), true, None)
            .await
            .unwrap();
        assert_eq!(actor.auth.get_state(), AuthState::Idle);
    }
}
