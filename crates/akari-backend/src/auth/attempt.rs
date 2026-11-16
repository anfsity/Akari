//! Owns active attempt resources, snapshots, cancellation, and signal ordering.
//!
//! The actor calls these operations serially. Leaving an active phase drops
//! [`AttemptResources`] directly from [`AuthStateMachine`], and interrupted
//! framing always discards its transport.

use std::time::Duration;

use tokio::{sync::watch, time::timeout};
use tokio_util::sync::CancellationToken;
use zbus::{fdo, object_server::SignalEmitter};

use crate::{
    greetd::{GreetdError, GreetdResponse, GreetdTransport},
    state::{ActiveAttempt, AuthState, AuthStateMachine, DetachedAttempt, StateEvent},
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

    pub(super) fn from_auth<R, T>(auth: &AuthStateMachine<R, T>, attempt_id: &str) -> Self {
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

/// Caller and cancellation lifetimes bound to the active attempt phase.
pub(super) struct AttemptResources {
    pub(super) caller: String,
    pub(super) cancellation: CancellationToken,
    caller_watcher: CancellationToken,
}

impl Drop for AttemptResources {
    fn drop(&mut self) {
        self.cancellation.cancel();
        self.caller_watcher.cancel();
    }
}

/// Distinguishes D-Bus caller cancellations from internal replacements and shutdowns.
pub(super) enum CancelScope<'a> {
    Caller {
        attempt_id: &'a str,
        caller: &'a str,
        allow_after_cleanup: bool,
    },
    Internal,
}

/// Mutable authentication state and signal publishers owned by `run_actor`.
pub(super) struct ActorState {
    pub(super) auth: AuthStateMachine<AttemptResources, GreetdTransport>,
    snapshots: watch::Sender<AuthSnapshot>,
    controls: watch::Sender<Option<AttemptControl>>,
    shutdown: CancellationToken,
}

impl ActorState {
    pub(super) fn new(
        snapshots: watch::Sender<AuthSnapshot>,
        controls: watch::Sender<Option<AttemptControl>>,
        shutdown: CancellationToken,
    ) -> Self {
        Self {
            auth: AuthStateMachine::default(),
            snapshots,
            controls,
            shutdown,
        }
    }

    pub(super) async fn begin_attempt(
        &mut self,
        caller: String,
        username: String,
        emitter: &SignalEmitter<'static>,
    ) -> fdo::Result<(String, CancellationToken, CancellationToken)> {
        let cancellation = self.shutdown.child_token();
        let watcher_token = CancellationToken::new();
        let attempt_id = self
            .auth
            .begin_authentication(username, |_| AttemptResources {
                caller: caller.clone(),
                cancellation: cancellation.clone(),
                caller_watcher: watcher_token.clone(),
            })
            .map_err(|error| fdo::Error::Failed(error.to_string()))?;

        tracing::Span::current().record("attempt_id", &attempt_id);
        tracing::info!(
            %attempt_id,
            %caller,
            state = self.auth.get_state().as_str(),
            "authentication started"
        );
        let _ = self.controls.send(Some(AttemptControl {
            caller,
            attempt_id: attempt_id.clone(),
            cancellation: cancellation.clone(),
        }));
        self.publish_snapshot(&attempt_id, Some(emitter)).await;

        Ok((attempt_id, cancellation, watcher_token))
    }

    pub(super) fn validate_owned_access(
        &self,
        attempt_id: &str,
        caller: &str,
    ) -> fdo::Result<(&ActiveAttempt<AttemptResources>, AuthState)> {
        let Some(active) = self.auth.get_active() else {
            return Err(fdo::Error::Failed("stale or unknown attempt id".to_owned()));
        };
        if active.id != attempt_id {
            return Err(fdo::Error::Failed("stale or unknown attempt id".to_owned()));
        }
        if active.resources.caller != caller {
            return Err(fdo::Error::AccessDenied(
                "authentication belongs to another D-Bus caller".to_owned(),
            ));
        }
        Ok((active, self.auth.get_state()))
    }

    pub(super) fn validate_owned_stage(
        &self,
        attempt_id: &str,
        caller: &str,
        expected: AuthState,
    ) -> fdo::Result<CancellationToken> {
        let (active, state) = self.validate_owned_access(attempt_id, caller)?;
        if state != expected {
            return Err(invalid_state_error(state));
        }
        Ok(active.resources.cancellation.clone())
    }

    pub(super) async fn begin_respond(
        &mut self,
        attempt_id: &str,
        caller: &str,
        emitter: &SignalEmitter<'_>,
    ) -> fdo::Result<(GreetdTransport, CancellationToken, String)> {
        let (active, state) = self.validate_owned_access(attempt_id, caller)?;
        let cancellation = active.resources.cancellation.clone();
        let username = active.username.clone();
        let Ok(transport) = self.auth.submit_response() else {
            return Err(invalid_state_error(state));
        };
        self.publish_snapshot(attempt_id, Some(emitter)).await;
        Ok((transport, cancellation, username))
    }

    pub(super) async fn resolve_session(
        &mut self,
        attempt_id: &str,
        emitter: &SignalEmitter<'_>,
    ) -> GreetdTransport {
        let transport = self
            .auth
            .resolve_session()
            .expect("validated ResolvingSession stage owns transport");
        self.publish_snapshot(attempt_id, Some(emitter)).await;
        transport
    }

    pub(super) async fn apply_transition(
        &mut self,
        attempt_id: &str,
        event: StateEvent<GreetdTransport>,
        emitter: Option<&SignalEmitter<'_>>,
    ) {
        self.auth
            .transition(sanitize_event_detail(event))
            .expect("authentication event matches the actor phase");
        if !self.auth.get_state().is_active() {
            let _ = self.controls.send(None);
        }
        self.publish_snapshot(attempt_id, emitter).await;
    }

    pub(super) async fn request_cancel(
        &mut self,
        emitter: Option<&SignalEmitter<'_>>,
    ) -> Option<DetachedAttempt<AttemptResources, GreetdTransport>> {
        let detached = self.auth.request_cancel().ok()?;
        let _ = self.controls.send(None);
        self.publish_snapshot(&detached.attempt.id, emitter).await;
        Some(detached)
    }

    async fn publish_snapshot(&self, attempt_id: &str, emitter: Option<&SignalEmitter<'_>>) {
        let snapshot = AuthSnapshot::from_auth(&self.auth, attempt_id);
        tracing::info!(%attempt_id, state = %snapshot.state, "authentication state changed");
        let _ = self.snapshots.send(snapshot.clone());
        emit_state_best_effort(emitter, snapshot).await;
    }
}

/// Transport failures always complete actor cleanup before returning to the
/// command loop. Connection and frame exchanges use the same cancellation and
/// failure transitions, so callers cannot accidentally leave an attempt alive.
pub(super) async fn handle_transport_result<T>(
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

pub(super) async fn cancel_current(
    actor: &mut ActorState,
    scope: CancelScope<'_>,
    emitter: Option<SignalEmitter<'static>>,
) -> fdo::Result<()> {
    validate_cancel_request(actor, scope)?;
    let Some(detached) = actor.request_cancel(emitter.as_ref()).await else {
        return Ok(());
    };
    let attempt_id = detached.attempt.id;
    let transport = detached.transport;
    tracing::info!(%attempt_id, "cancelling authentication");
    // Drop AttemptResources before cancelling greetd so the caller watcher and
    // attempt token are already cancelled during the bounded cancel exchange.
    drop(detached.attempt.resources);

    let cancel_result = if let Some(mut transport) = transport {
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
    // Drop the transport rather than sending another request over a socket whose
    // next frame boundary is no longer known.
    tracing::info!(%attempt_id, state = actor.auth.get_state().as_str(), "cancelling authentication");
    let detached = actor
        .request_cancel(emitter)
        .await
        .expect("cancelled transaction owns an active attempt");
    debug_assert_eq!(detached.attempt.id, attempt_id);
    drop(detached);
    actor
        .apply_transition(attempt_id, StateEvent::CancellationFinished, emitter)
        .await;

    tracing::info!(%attempt_id, "authentication cancelled; transport closed");
    fdo::Error::Failed("authentication attempt was cancelled".to_owned())
}

pub(super) async fn fail_transaction(
    actor: &mut ActorState,
    attempt_id: &str,
    error: GreetdError,
    emitter: &SignalEmitter<'static>,
) -> fdo::Error {
    tracing::error!(%attempt_id, error = ?error, state = actor.auth.get_state().as_str(), "authentication transaction failed");
    let detail = sanitize_detail(&error.to_string());
    debug_assert!(actor.auth.is_current_attempt(attempt_id));
    actor
        .apply_transition(
            attempt_id,
            StateEvent::ProtocolFailure {
                detail: detail.clone(),
            },
            Some(emitter),
        )
        .await;
    fdo::Error::Failed(detail)
}

pub(super) async fn emit_prompt_best_effort(
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

fn validate_cancel_request(actor: &ActorState, scope: CancelScope<'_>) -> fdo::Result<()> {
    match scope {
        CancelScope::Internal => Ok(()),
        CancelScope::Caller {
            attempt_id,
            caller,
            allow_after_cleanup,
        } => {
            // An explicit Cancel that already interrupted its owned token may
            // arrive after I/O cleanup returned to Idle. Only that acknowledged
            // interruption permits success here; a delayed watcher must still
            // reject a stale target.
            if allow_after_cleanup && actor.auth.get_state() == AuthState::Idle {
                return Ok(());
            }
            actor.validate_owned_access(attempt_id, caller).map(|_| ())
        }
    }
}

fn invalid_state_error(state: AuthState) -> fdo::Error {
    fdo::Error::Failed(format!(
        "operation is not valid in state {}",
        state.as_str()
    ))
}

fn sanitize_event_detail<T>(event: StateEvent<T>) -> StateEvent<T> {
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
        ActorState, AttemptResources, AuthSnapshot, CancelScope, cancel_current, sanitize_detail,
        sanitize_event_detail, validate_cancel_request,
    };
    use crate::state::{AuthState, AuthStateMachine, StateEvent};

    fn test_actor() -> ActorState {
        let (snapshots, _) = watch::channel(AuthSnapshot::idle());
        let (controls, _) = watch::channel(None);
        ActorState::new(snapshots, controls, CancellationToken::new())
    }

    fn begin_test_attempt(actor: &mut ActorState, caller: &str) -> String {
        actor
            .auth
            .begin_authentication("alice".to_owned(), |_| AttemptResources {
                caller: caller.to_owned(),
                cancellation: CancellationToken::new(),
                caller_watcher: CancellationToken::new(),
            })
            .unwrap()
            .clone()
    }

    fn cancelled_actor() -> (ActorState, String) {
        let mut actor = test_actor();
        let attempt_id = begin_test_attempt(&mut actor, ":1.1");
        actor.auth.request_cancel().unwrap();
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
        assert!(
            validate_cancel_request(
                &actor,
                CancelScope::Caller {
                    attempt_id: &attempt_id,
                    caller: ":1.1",
                    allow_after_cleanup: false,
                },
            )
            .is_err()
        );
    }

    #[test]
    fn cancel_is_idempotent_after_cleanup() {
        let (actor, attempt_id) = cancelled_actor();

        assert!(
            validate_cancel_request(
                &actor,
                CancelScope::Caller {
                    attempt_id: &attempt_id,
                    caller: ":1.1",
                    allow_after_cleanup: true,
                },
            )
            .is_ok()
        );
    }

    #[test]
    fn validates_owned_current_attempt_and_stage() {
        let mut actor = test_actor();
        let attempt_id = begin_test_attempt(&mut actor, ":1.1");

        assert!(actor.validate_owned_access(&attempt_id, ":1.1").is_ok());
        assert!(actor.validate_owned_access(&attempt_id, ":1.2").is_err());
        assert!(
            actor
                .validate_owned_access("attempt-stale", ":1.1")
                .is_err()
        );
        assert!(
            actor
                .validate_owned_stage(&attempt_id, ":1.1", AuthState::CreatingSession)
                .is_ok()
        );
        assert!(
            actor
                .validate_owned_stage(&attempt_id, ":1.1", AuthState::WaitingForInput)
                .is_err()
        );
    }

    #[test]
    fn snapshot_has_state_and_detail() {
        let mut auth = AuthStateMachine::<(), ()>::default();
        let attempt_id = auth
            .begin_authentication("alice".to_owned(), |_| ())
            .unwrap();
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

        let StateEvent::<()>::SessionUnavailable {
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
        let attempt_id = begin_test_attempt(&mut actor, ":1.1");

        cancel_current(&mut actor, CancelScope::Internal, None)
            .await
            .unwrap();

        cancel_current(
            &mut actor,
            CancelScope::Caller {
                attempt_id: &attempt_id,
                caller: ":1.1",
                allow_after_cleanup: true,
            },
            None,
        )
        .await
        .unwrap();
        assert_eq!(actor.auth.get_state(), AuthState::Idle);
    }

    #[tokio::test]
    async fn leaving_active_state_drops_resources_and_clears_control() {
        let (snapshots, _) = watch::channel(AuthSnapshot::idle());
        let (controls, controls_rx) = watch::channel(None);
        let mut actor = ActorState::new(snapshots, controls, CancellationToken::new());
        let attempt_id = begin_test_attempt(&mut actor, ":1.1");
        let cancellation = actor
            .auth
            .get_active()
            .unwrap()
            .resources
            .cancellation
            .clone();
        let _ = actor.controls.send(Some(super::AttemptControl {
            caller: ":1.1".to_owned(),
            attempt_id: attempt_id.clone(),
            cancellation: cancellation.clone(),
        }));

        actor
            .apply_transition(
                &attempt_id,
                StateEvent::ProtocolFailure {
                    detail: "failed".to_owned(),
                },
                None,
            )
            .await;

        assert_eq!(actor.auth.get_state(), AuthState::Failed);
        assert!(cancellation.is_cancelled());
        assert!(controls_rx.borrow().is_none());
    }

    #[tokio::test]
    async fn failed_state_allows_replacement_and_internal_cancel_is_safe() {
        let mut actor = test_actor();
        let attempt_id = begin_test_attempt(&mut actor, ":1.1");
        actor
            .apply_transition(
                &attempt_id,
                StateEvent::ProtocolFailure {
                    detail: "failed".to_owned(),
                },
                None,
            )
            .await;
        assert_eq!(actor.auth.get_state(), AuthState::Failed);

        cancel_current(&mut actor, CancelScope::Internal, None)
            .await
            .unwrap();
        assert_eq!(actor.auth.get_state(), AuthState::Failed);

        let next_id = begin_test_attempt(&mut actor, ":1.1");
        assert_ne!(attempt_id, next_id);
        assert_eq!(actor.auth.get_state(), AuthState::CreatingSession);
    }
}
