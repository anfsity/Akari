//! Serializes accepted commands and authentication work through one queue.

use tokio::sync::{mpsc, oneshot, watch};
use tokio_util::sync::CancellationToken;
use tracing::Instrument;
use zbus::fdo;

use super::{
    attempt::{
        ActorState, AttemptControl, AuthSnapshot, CancelScope, cancel_current, finish_cancellation,
    },
    flow::{
        begin_session_resolution, create_attempt, fail_session_resolution, handle_start_session,
        report_session_unavailable, run_authentication, run_respond,
    },
    handle::{AuthCommand, BeginSequenceMap},
};

fn consume_begin_sequence(latest_begin: &BeginSequenceMap, caller: &str, sequence: u64) -> bool {
    let mut sequences = latest_begin.lock().expect("begin sequence mutex");
    match sequences.get(caller).copied() {
        Some(latest) if latest > sequence => true,
        Some(_) => {
            sequences.remove(caller);
            false
        }
        None => false,
    }
}

fn send_reply<T>(reply: oneshot::Sender<fdo::Result<T>>, result: fdo::Result<T>) {
    if let Err(error) = &result {
        tracing::warn!(%error, "authentication operation rejected or failed");
    }
    if reply.send(result).is_err() {
        tracing::debug!("authentication method caller no longer awaiting reply");
    }
}

struct ActorContext<'a> {
    actor: ActorState,
    command_sender: &'a mpsc::WeakSender<AuthCommand>,
    latest_begin: &'a BeginSequenceMap,
}

pub(super) async fn run_actor(
    mut commands: mpsc::Receiver<AuthCommand>,
    command_sender: mpsc::WeakSender<AuthCommand>,
    snapshots: watch::Sender<AuthSnapshot>,
    controls: watch::Sender<Option<AttemptControl>>,
    latest_begin: BeginSequenceMap,
    shutdown: CancellationToken,
) {
    // Only external handles keep the command channel alive. Disconnect watchers
    // use weak senders so releasing the service can reach the final cleanup even
    // if an attempt watcher is still waiting for a bus event.
    let mut context = ActorContext {
        actor: ActorState::new(snapshots, controls, shutdown.clone()),
        command_sender: &command_sender,
        latest_begin: &latest_begin,
    };
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
                .or_else(|| context.actor.auth.find_active_attempt_id()),
        };
        let span = tracing::info_span!(
            "authentication",
            operation = command.get_operation(),
            caller = command.get_caller().unwrap_or("runtime"),
            attempt_id = initial_attempt_id,
            initial_state = context.actor.auth.get_state().as_str(),
        );
        async {
            tracing::debug!("processing authentication operation");
            handle_command(&mut context, command).await;
        }
        .instrument(span)
        .await;
    }

    let _ = cancel_current(&mut context.actor, CancelScope::Internal, None).await;
}

async fn handle_command(context: &mut ActorContext<'_>, command: AuthCommand) {
    match command {
        #[cfg(test)]
        AuthCommand::Panic => panic!("test actor failure"),
        AuthCommand::Begin {
            caller,
            username,
            sequence,
            emitter,
            reply,
        } => {
            handle_begin_command(context, caller, username, sequence, emitter, reply).await;
        }
        AuthCommand::Respond {
            caller,
            attempt_id,
            response,
            emitter,
            reply,
        } => {
            handle_respond_command(
                &mut context.actor,
                caller,
                attempt_id,
                response,
                emitter,
                reply,
            )
            .await;
        }
        AuthCommand::Cancel {
            attempt_id,
            caller,
            allow_after_cleanup,
            emitter,
            reply,
        } => {
            let result = cancel_current(
                &mut context.actor,
                CancelScope::Caller {
                    attempt_id: &attempt_id,
                    caller: &caller,
                    allow_after_cleanup,
                },
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
            let result =
                begin_session_resolution(&mut context.actor, &attempt_id, &caller, &emitter).await;
            send_reply(reply, result);
        }
        AuthCommand::ReportSessionUnavailable {
            caller,
            attempt_id,
            detail,
            emitter,
            reply,
        } => {
            let result = report_session_unavailable(
                &mut context.actor,
                &attempt_id,
                &caller,
                detail,
                &emitter,
            )
            .await;
            send_reply(reply, result);
        }
        AuthCommand::FailSessionResolution {
            caller,
            attempt_id,
            detail,
            emitter,
            reply,
        } => {
            let result =
                fail_session_resolution(&mut context.actor, &attempt_id, &caller, detail, &emitter)
                    .await;
            send_reply(reply, result);
        }
        AuthCommand::StartSession {
            caller,
            attempt_id,
            session,
            emitter,
            reply,
        } => {
            let result =
                handle_start_session(&mut context.actor, &attempt_id, &caller, session, emitter)
                    .await;
            send_reply(reply, result);
        }
    }
}

async fn handle_begin_command(
    context: &mut ActorContext<'_>,
    caller: String,
    username: String,
    sequence: u64,
    emitter: zbus::object_server::SignalEmitter<'static>,
    reply: oneshot::Sender<fdo::Result<String>>,
) {
    let (attempt_id, cancellation) = match create_attempt(
        &mut context.actor,
        caller.clone(),
        username.clone(),
        &emitter,
        context.command_sender,
    )
    .await
    {
        Ok(created) => created,
        Err(error) => {
            let _ = consume_begin_sequence(context.latest_begin, &caller, sequence);
            send_reply(reply, Err(error));
            return;
        }
    };
    let superseded = consume_begin_sequence(context.latest_begin, &caller, sequence);
    // Bind the UI to the attempt before PAM starts waiting for a camera or
    // other passive factor. Protocol failures are reported via state signals.
    send_reply(reply, Ok(attempt_id.clone()));
    if superseded {
        let _ = finish_cancellation(&mut context.actor, &attempt_id, Some(&emitter)).await;
        return;
    }
    let _ = run_authentication(
        &mut context.actor,
        &attempt_id,
        &username,
        emitter,
        &cancellation,
    )
    .await;
}

async fn handle_respond_command(
    actor: &mut ActorState,
    caller: String,
    attempt_id: String,
    response: zeroize::Zeroizing<String>,
    emitter: zbus::object_server::SignalEmitter<'static>,
    reply: oneshot::Sender<fdo::Result<()>>,
) {
    let (transport, cancellation, username) =
        match actor.begin_respond(&attempt_id, &caller, &emitter).await {
            Ok(accepted) => accepted,
            Err(error) => {
                send_reply(reply, Err(error));
                return;
            }
        };
    // Acknowledge once SubmittingResponse is committed so slow PAM factors or
    // automatic auth_error retries do not time out the D-Bus reply.
    send_reply(reply, Ok(()));
    let _ = run_respond(
        actor,
        &attempt_id,
        transport,
        response,
        &username,
        emitter,
        &cancellation,
    )
    .await;
}

#[cfg(test)]
mod tests {
    use std::{
        collections::HashMap,
        sync::{Arc, Mutex},
    };

    use super::consume_begin_sequence;

    #[test]
    fn pipelined_begin_sequence_detects_superseding_caller_calls_and_cleans_latest() {
        let latest = Arc::new(Mutex::new(HashMap::from([
            (":1.1".to_owned(), 2_u64),
            (":1.2".to_owned(), 1_u64),
        ])));
        assert!(consume_begin_sequence(&latest, ":1.1", 1));
        assert!(!consume_begin_sequence(&latest, ":1.1", 2));
        assert!(!latest.lock().unwrap().contains_key(":1.1"));
        assert!(!consume_begin_sequence(&latest, ":1.2", 1));
        assert!(latest.lock().unwrap().is_empty());
    }
}
