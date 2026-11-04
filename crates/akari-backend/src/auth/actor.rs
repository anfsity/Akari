//! Serializes accepted commands and authentication work through one queue.

use tokio::sync::{mpsc, oneshot, watch};
use tokio_util::sync::CancellationToken;
use tracing::Instrument;
use zbus::fdo;

use super::{
    attempt::{
        ActorState, AttemptControl, AuthSnapshot, begin_session_resolution, cancel_current,
        create_attempt, fail_session_resolution, handle_respond, handle_start_session,
        report_session_unavailable, run_authentication, validate_owned_attempt,
    },
    handle::AuthCommand,
};

fn send_reply<T>(reply: oneshot::Sender<fdo::Result<T>>, result: fdo::Result<T>) {
    if let Err(error) = &result {
        tracing::warn!(%error, "authentication operation rejected or failed");
    }
    if reply.send(result).is_err() {
        tracing::debug!("authentication method caller no longer awaiting reply");
    }
}

pub(super) async fn run_actor(
    mut commands: mpsc::Receiver<AuthCommand>,
    command_sender: mpsc::WeakSender<AuthCommand>,
    snapshots: watch::Sender<AuthSnapshot>,
    controls: watch::Sender<Option<AttemptControl>>,
    shutdown: CancellationToken,
) {
    // Only external handles keep the command channel alive. Disconnect watchers
    // use weak senders so releasing the service can reach the final cleanup even
    // if an attempt watcher is still waiting for a bus event.
    let mut actor = ActorState::new(snapshots, controls, shutdown.clone());
    loop {
        let command = tokio::select! {
            biased;
            _ = shutdown.cancelled() => break,
            command = commands.recv() => command,
        };
        let Some(command) = command else {
            break;
        };
        let initial_attempt_id = match &command {
            AuthCommand::Begin { .. } => None,
            _ => command
                .get_attempt_id()
                .or_else(|| actor.auth.find_active_attempt_id()),
        };
        let span = tracing::info_span!(
            "authentication",
            operation = command.get_operation(),
            caller = command.get_caller().unwrap_or("runtime"),
            attempt_id = initial_attempt_id,
            initial_state = actor.auth.get_state().as_str(),
        );
        async {
            tracing::debug!("processing authentication operation");
            match command {
                #[cfg(test)]
                AuthCommand::Panic => panic!("test actor failure"),
                AuthCommand::Begin {
                    caller,
                    username,
                    emitter,
                    reply,
                } => {
                    let attempt_id = match create_attempt(
                        &mut actor,
                        caller,
                        username.clone(),
                        &emitter,
                        &command_sender,
                    )
                    .await
                    {
                        Ok(attempt_id) => attempt_id,
                        Err(error) => {
                            send_reply(reply, Err(error));
                            return;
                        }
                    };
                    // Bind the UI to the attempt before PAM starts waiting for
                    // a camera or other passive factor. Protocol failures are
                    // then reported through the attempt's state signals.
                    send_reply(reply, Ok(attempt_id.clone()));
                    let _ = run_authentication(&mut actor, &attempt_id, &username, emitter).await;
                }
                AuthCommand::Respond {
                    caller,
                    attempt_id,
                    response,
                    emitter,
                    reply,
                } => {
                    if let Err(error) = validate_owned_attempt(&actor, &attempt_id, &caller) {
                        send_reply(reply, Err(error));
                        return;
                    }
                    let result = handle_respond(&mut actor, &attempt_id, response, emitter).await;
                    send_reply(reply, result);
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
                    )
                    .await;
                    send_reply(reply, result);
                }
                AuthCommand::BeginSessionResolution {
                    caller,
                    attempt_id,
                    emitter,
                    reply,
                } => {
                    if let Err(error) = validate_owned_attempt(&actor, &attempt_id, &caller) {
                        send_reply(reply, Err(error));
                        return;
                    }
                    let result = begin_session_resolution(&mut actor, &attempt_id, &emitter).await;
                    send_reply(reply, result);
                }
                AuthCommand::ReportSessionUnavailable {
                    caller,
                    attempt_id,
                    detail,
                    emitter,
                    reply,
                } => {
                    if let Err(error) = validate_owned_attempt(&actor, &attempt_id, &caller) {
                        send_reply(reply, Err(error));
                        return;
                    }
                    let result =
                        report_session_unavailable(&mut actor, &attempt_id, detail, &emitter).await;
                    send_reply(reply, result);
                }
                AuthCommand::FailSessionResolution {
                    caller,
                    attempt_id,
                    detail,
                    emitter,
                    reply,
                } => {
                    if let Err(error) = validate_owned_attempt(&actor, &attempt_id, &caller) {
                        send_reply(reply, Err(error));
                        return;
                    }
                    let result =
                        fail_session_resolution(&mut actor, &attempt_id, detail, &emitter).await;
                    send_reply(reply, result);
                }
                AuthCommand::StartSession {
                    caller,
                    attempt_id,
                    session,
                    emitter,
                    reply,
                } => {
                    if let Err(error) = validate_owned_attempt(&actor, &attempt_id, &caller) {
                        send_reply(reply, Err(error));
                        return;
                    }
                    let result =
                        handle_start_session(&mut actor, &attempt_id, session, emitter).await;
                    send_reply(reply, result);
                }
            }
        }
        .instrument(span)
        .await;
    }

    let _ = cancel_current(&mut actor, None, None, false, None).await;
}
