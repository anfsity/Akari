//! Observes the D-Bus caller without keeping the actor's command queue alive.

use futures_util::StreamExt;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

use super::handle::{AuthCommand, send_command};

pub(super) fn spawn_caller_watcher(
    connection: zbus::Connection,
    caller: String,
    attempt_id: String,
    watcher_token: CancellationToken,
    cancellation: CancellationToken,
    commands: mpsc::WeakSender<AuthCommand>,
) {
    // D-Bus may remove the caller while the original request is blocked in
    // greetd, so this watcher must outlive the initiating method call.
    tokio::spawn(async move {
        let disconnected = tokio::select! {
            biased;
            _ = watcher_token.cancelled() => false,
            disconnected = wait_for_caller_disconnect(&connection, &caller, &attempt_id) => disconnected,
        };
        if disconnected && !watcher_token.is_cancelled() {
            cancel_for_caller_disconnect(commands, attempt_id, caller, cancellation).await;
        }
    });
}

async fn wait_for_caller_disconnect(
    connection: &zbus::Connection,
    caller: &str,
    attempt_id: &str,
) -> bool {
    let proxy = match zbus::fdo::DBusProxy::new(connection).await {
        Ok(proxy) => proxy,
        Err(error) => {
            tracing::warn!(%attempt_id, %caller, error = ?error, "could not create D-Bus disconnect watcher");
            return true;
        }
    };
    let mut stream = match proxy
        .receive_name_owner_changed_with_args(&[(0, caller), (2, "")])
        .await
    {
        Ok(stream) => stream,
        Err(error) => {
            tracing::warn!(%attempt_id, %caller, error = ?error, "could not subscribe to D-Bus client disconnects");
            return true;
        }
    };
    let caller_name = caller
        .try_into()
        .expect("D-Bus sender is a unique bus name");
    // Subscribe before checking ownership: checking first would miss a
    // caller that disconnects between the check and signal registration.
    if !proxy.name_has_owner(caller_name).await.unwrap_or(false) {
        return true;
    }
    stream.next().await;
    true
}

async fn cancel_for_caller_disconnect(
    commands: mpsc::WeakSender<AuthCommand>,
    attempt_id: String,
    caller: String,
    cancellation: CancellationToken,
) {
    tracing::info!(%attempt_id, %caller, operation = "CallerDisconnected", "cancelling authentication after caller disconnect");
    cancellation.cancel();
    let Some(commands) = commands.upgrade() else {
        return;
    };
    let _ = send_command(&commands, |reply| AuthCommand::Cancel {
        attempt_id,
        caller,
        allow_after_cleanup: false,
        emitter: None,
        reply,
    })
    .await;
}
