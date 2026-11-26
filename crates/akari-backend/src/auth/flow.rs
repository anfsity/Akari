//! Serialized authentication and session-start protocol flows.

use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;
use zbus::{fdo, object_server::SignalEmitter};

use super::{
    attempt::{
        ActorState, CancelScope, cancel_current, emit_prompt_best_effort, fail_transaction,
        finish_cancellation, handle_transport_result, sanitize_detail,
    },
    caller_watch::spawn_caller_watcher,
    handle::AuthCommand,
};
use crate::{
    greetd::{GreetdError, GreetdResponse, GreetdTransport},
    session_catalog::SessionEntry,
    session_launch::create_session_launch,
    state::{AuthState, StateEvent},
};

const MAX_AUTO_ACKNOWLEDGE_MESSAGES: usize = 64;

#[derive(Clone, Copy)]
enum PromptDisposition {
    NeedsInput,
    AutoAcknowledge,
}

enum ErrorOutcome {
    Retry(GreetdTransport, GreetdResponse),
    Abort(fdo::Error),
}

struct AuthExchange<'a> {
    attempt_id: &'a str,
    username: &'a str,
    emitter: &'a SignalEmitter<'static>,
    cancellation: &'a CancellationToken,
}

pub(super) async fn create_attempt(
    actor: &mut ActorState,
    caller: String,
    username: String,
    emitter: &SignalEmitter<'static>,
    commands: &mpsc::WeakSender<AuthCommand>,
) -> fdo::Result<(String, CancellationToken)> {
    if let Some(active) = actor.auth.get_active() {
        if active.resources.caller != caller {
            return Err(fdo::Error::AccessDenied(
                "authentication belongs to another D-Bus caller".to_owned(),
            ));
        }
        if let Err(error) = cancel_current(actor, CancelScope::Internal, None).await {
            tracing::warn!(
                %caller,
                %error,
                "previous attempt transport cancellation failed during replacement"
            );
        }
    }

    let (attempt_id, cancellation, watcher_token) = actor
        .begin_attempt(caller.clone(), username, emitter)
        .await?;
    spawn_caller_watcher(
        emitter.connection().clone(),
        caller,
        attempt_id.clone(),
        watcher_token,
        cancellation.clone(),
        commands.clone(),
    );

    Ok((attempt_id, cancellation))
}

pub(super) async fn run_authentication(
    actor: &mut ActorState,
    attempt_id: &str,
    username: &str,
    emitter: SignalEmitter<'static>,
    cancellation: &CancellationToken,
) -> fdo::Result<()> {
    // I/O stays in the same actor command after acceptance, so cancellation
    // still finishes cleanup before a replacement transaction can start.
    let result = connect_and_create_session(username, cancellation).await;
    let (transport, response) =
        handle_transport_result(actor, attempt_id, result, &emitter).await?;

    let exchange = AuthExchange {
        attempt_id,
        username,
        emitter: &emitter,
        cancellation,
    };
    consume_response(actor, &exchange, transport, response, false).await
}

pub(super) async fn run_respond(
    actor: &mut ActorState,
    attempt_id: &str,
    mut transport: GreetdTransport,
    response: zeroize::Zeroizing<String>,
    username: &str,
    emitter: SignalEmitter<'static>,
    cancellation: &CancellationToken,
) -> fdo::Result<()> {
    let result = transport
        .post_auth_message_response(Some(response.as_str()), cancellation)
        .await;
    drop(response);
    let next_response = handle_transport_result(actor, attempt_id, result, &emitter).await?;

    let exchange = AuthExchange {
        attempt_id,
        username,
        emitter: &emitter,
        cancellation,
    };
    consume_response(actor, &exchange, transport, next_response, true).await
}

pub(super) async fn begin_session_resolution(
    actor: &mut ActorState,
    attempt_id: &str,
    caller: &str,
    emitter: &SignalEmitter<'static>,
) -> fdo::Result<()> {
    actor.validate_owned_stage(attempt_id, caller, AuthState::Authenticated)?;
    actor
        .apply_transition(attempt_id, StateEvent::StartSessionRequested, Some(emitter))
        .await;
    Ok(())
}

pub(super) async fn report_session_unavailable(
    actor: &mut ActorState,
    attempt_id: &str,
    caller: &str,
    detail: String,
    emitter: &SignalEmitter<'static>,
) -> fdo::Result<()> {
    actor.validate_owned_stage(attempt_id, caller, AuthState::ResolvingSession)?;
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
    caller: &str,
    detail: String,
    emitter: &SignalEmitter<'static>,
) -> fdo::Result<()> {
    actor.validate_owned_stage(attempt_id, caller, AuthState::ResolvingSession)?;
    actor
        .apply_transition(
            attempt_id,
            StateEvent::ProtocolFailure { detail },
            Some(emitter),
        )
        .await;
    Ok(())
}

pub(super) async fn handle_start_session(
    actor: &mut ActorState,
    attempt_id: &str,
    caller: &str,
    session: SessionEntry,
    emitter: SignalEmitter<'static>,
) -> fdo::Result<()> {
    let cancellation =
        actor.validate_owned_stage(attempt_id, caller, AuthState::ResolvingSession)?;
    let (command, environment) = match create_session_launch(&session) {
        Ok(launch) => launch,
        Err(error) => {
            let detail =
                sanitize_detail(&format!("could not prepare user session launcher: {error}"));
            tracing::error!(%attempt_id, error = ?error, "user session launcher preparation failed");
            actor
                .apply_transition(
                    attempt_id,
                    StateEvent::ProtocolFailure {
                        detail: detail.clone(),
                    },
                    Some(&emitter),
                )
                .await;
            return Err(fdo::Error::Failed(detail));
        }
    };

    let mut transport = actor.resolve_session(attempt_id, &emitter).await;
    tracing::info!(
        %attempt_id,
        session_id = %session.session_id,
        source = %session.source.display(),
        state = actor.auth.get_state().as_str(),
        "starting desktop session"
    );
    let response = transport
        .start_session(&command, &environment, &cancellation)
        .await;
    let response = handle_transport_result(actor, attempt_id, response, &emitter).await?;

    match response {
        GreetdResponse::Success => {
            tracing::info!(%attempt_id, session_id = %session.session_id, "desktop session accepted by greetd");
            actor
                .apply_transition(attempt_id, StateEvent::SessionStarted, Some(&emitter))
                .await;
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

async fn connect_and_create_session(
    username: &str,
    cancellation: &CancellationToken,
) -> Result<(GreetdTransport, GreetdResponse), GreetdError> {
    let mut transport = GreetdTransport::connect(cancellation).await?;
    let response = transport.create_session(username, cancellation).await?;
    Ok((transport, response))
}

async fn consume_response(
    actor: &mut ActorState,
    exchange: &AuthExchange<'_>,
    mut transport: GreetdTransport,
    mut response: GreetdResponse,
    mut user_response_submitted: bool,
) -> fdo::Result<()> {
    // One greetd response can require several follow-up frames: visible and
    // secret prompts wait for the UI, while informational messages are
    // acknowledged automatically and continue the same transaction.
    let mut auto_acknowledged = 0_usize;
    loop {
        if exchange.cancellation.is_cancelled() {
            return Err(
                finish_cancellation(actor, exchange.attempt_id, Some(exchange.emitter)).await,
            );
        }
        match response {
            GreetdResponse::Success => {
                tracing::info!(
                    attempt_id = %exchange.attempt_id,
                    state = actor.auth.get_state().as_str(),
                    "authentication succeeded"
                );
                actor
                    .apply_transition(
                        exchange.attempt_id,
                        StateEvent::AuthenticationSucceeded(transport),
                        Some(exchange.emitter),
                    )
                    .await;
                return Ok(());
            }
            GreetdResponse::Error {
                error_type,
                description,
            } => {
                match handle_error_response(
                    actor,
                    exchange,
                    transport,
                    error_type,
                    description,
                    user_response_submitted,
                )
                .await
                {
                    ErrorOutcome::Retry(next_transport, next_response) => {
                        transport = next_transport;
                        response = next_response;
                        user_response_submitted = false;
                        auto_acknowledged = 0;
                    }
                    ErrorOutcome::Abort(error) => return Err(error),
                }
            }
            GreetdResponse::AuthMessage {
                auth_message_type,
                auth_message,
            } => {
                match handle_auth_message(
                    actor,
                    exchange,
                    transport,
                    auth_message_type,
                    auth_message,
                    &mut auto_acknowledged,
                )
                .await?
                {
                    Some((next_transport, next_response)) => {
                        transport = next_transport;
                        response = next_response;
                    }
                    None => return Ok(()),
                }
            }
        }
    }
}

async fn handle_auth_message(
    actor: &mut ActorState,
    exchange: &AuthExchange<'_>,
    mut transport: GreetdTransport,
    auth_message_type: String,
    auth_message: String,
    auto_acknowledged: &mut usize,
) -> fdo::Result<Option<(GreetdTransport, GreetdResponse)>> {
    let disposition = match auth_message_type.as_str() {
        "visible" | "secret" => PromptDisposition::NeedsInput,
        "info" | "error" => {
            if *auto_acknowledged >= MAX_AUTO_ACKNOWLEDGE_MESSAGES {
                return Err(fail_transaction(
                    actor,
                    exchange.attempt_id,
                    GreetdError::UnexpectedResponse(
                        "authentication emitted too many informational messages".to_owned(),
                    ),
                    exchange.emitter,
                )
                .await);
            }
            *auto_acknowledged += 1;
            PromptDisposition::AutoAcknowledge
        }
        _ => {
            return Err(fail_transaction(
                actor,
                exchange.attempt_id,
                GreetdError::UnexpectedResponse(format!(
                    "unsupported authentication message type: {auth_message_type}"
                )),
                exchange.emitter,
            )
            .await);
        }
    };
    actor
        .apply_transition(
            exchange.attempt_id,
            StateEvent::AuthMessage,
            Some(exchange.emitter),
        )
        .await;
    if exchange.cancellation.is_cancelled() {
        return Err(finish_cancellation(actor, exchange.attempt_id, Some(exchange.emitter)).await);
    }
    emit_prompt_best_effort(
        exchange.emitter,
        exchange.attempt_id,
        &auth_message_type,
        auth_message,
        exchange.cancellation,
    )
    .await;
    if exchange.cancellation.is_cancelled() {
        return Err(finish_cancellation(actor, exchange.attempt_id, Some(exchange.emitter)).await);
    }
    match disposition {
        PromptDisposition::NeedsInput => {
            actor
                .apply_transition(
                    exchange.attempt_id,
                    StateEvent::PromptNeedsInput(transport),
                    Some(exchange.emitter),
                )
                .await;
            Ok(None)
        }
        PromptDisposition::AutoAcknowledge => {
            actor
                .apply_transition(
                    exchange.attempt_id,
                    StateEvent::PromptAutoResponse,
                    Some(exchange.emitter),
                )
                .await;
            let result = transport
                .post_auth_message_response(None, exchange.cancellation)
                .await;
            let next_response =
                handle_transport_result(actor, exchange.attempt_id, result, exchange.emitter)
                    .await?;
            Ok(Some((transport, next_response)))
        }
    }
}

async fn handle_error_response(
    actor: &mut ActorState,
    exchange: &AuthExchange<'_>,
    mut transport: GreetdTransport,
    error_type: String,
    description: String,
    user_response_submitted: bool,
) -> ErrorOutcome {
    let detail = sanitize_detail(&format!("{error_type}: {description}"));
    // greetd 0.10 retains its configuring slot after PAM failure.
    // Cancel removes that slot before contacting the dead worker, so even its
    // Error response completes server-side cleanup. Transport failures and
    // unexpected prompts remain failures.
    let result = transport.cancel_session(exchange.cancellation).await;
    let cancel_response =
        match handle_transport_result(actor, exchange.attempt_id, result, exchange.emitter).await {
            Ok(response) => response,
            Err(error) => return ErrorOutcome::Abort(error),
        };
    drop(transport);

    if matches!(cancel_response, GreetdResponse::AuthMessage { .. }) {
        return ErrorOutcome::Abort(
            fail_transaction(
                actor,
                exchange.attempt_id,
                GreetdError::UnexpectedResponse(
                    "unexpected prompt while cancelling rejected authentication".to_owned(),
                ),
                exchange.emitter,
            )
            .await,
        );
    }

    // Automatic info/error acknowledgments also use SubmittingResponse. Only a
    // conversation with user input may restart on rejection; otherwise PAM
    // failures can loop and consume login attempts without anyone responding.
    if error_type == "auth_error" && user_response_submitted {
        tracing::info!(
            attempt_id = %exchange.attempt_id,
            %error_type,
            state = actor.auth.get_state().as_str(),
            "credential rejected; retrying authentication"
        );
        actor
            .apply_transition(
                exchange.attempt_id,
                StateEvent::CredentialRejected {
                    detail: detail.clone(),
                },
                Some(exchange.emitter),
            )
            .await;
        emit_prompt_best_effort(
            exchange.emitter,
            exchange.attempt_id,
            "error",
            detail,
            exchange.cancellation,
        )
        .await;

        let result = connect_and_create_session(exchange.username, exchange.cancellation).await;
        return match handle_transport_result(actor, exchange.attempt_id, result, exchange.emitter)
            .await
        {
            Ok((next_transport, next_response)) => {
                ErrorOutcome::Retry(next_transport, next_response)
            }
            Err(error) => ErrorOutcome::Abort(error),
        };
    }

    tracing::warn!(
        attempt_id = %exchange.attempt_id,
        %error_type,
        state = actor.auth.get_state().as_str(),
        "authentication rejected by greetd"
    );
    actor
        .apply_transition(
            exchange.attempt_id,
            StateEvent::AuthenticationFailed {
                detail: detail.clone(),
            },
            Some(exchange.emitter),
        )
        .await;
    ErrorOutcome::Abort(fdo::Error::Failed(detail))
}
