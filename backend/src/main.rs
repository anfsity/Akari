//! Process lifetime for the D-Bus service and its authentication actor.
//! A stopped actor cannot leave a live service answering stale snapshots;
//! runtime observes task completion as well as signals, bus loss, and handoff.

mod auth;
mod greetd;
mod service;
mod session_catalog;
mod session_launch;
mod state;
mod users;

use std::{error::Error, sync::Arc};

use service::{BUS_NAME, GreeterService, OBJECT_PATH};
use tokio::{
    signal::unix::{SignalKind, signal},
    sync::Notify,
};
use tracing_subscriber::EnvFilter;
use zbus::connection::Builder;

type AppResult<T> = Result<T, Box<dyn Error + Send + Sync>>;

fn main() -> AppResult<()> {
    let arguments: Vec<_> = std::env::args_os().skip(1).collect();
    match arguments.as_slice() {
        [] => run_backend(),
        [arg] if arg == session_launch::START_SESSION => {
            session_launch::start_session().map_err(Into::into)
        }
        [arg] if arg == session_launch::EXEC_DESKTOP => {
            session_launch::exec_desktop().map_err(Into::into)
        }
        _ => Err("expected no arguments, --start-session or --exec-desktop".into()),
    }
}

#[tokio::main]
async fn run_backend() -> AppResult<()> {
    if let Err(error) = init_tracing() {
        eprintln!("event=startup_failed operation=InitTracing error={error:?}");
        return Err(error);
    }
    let result = run().await;
    if let Err(error) = &result {
        tracing::error!(event = "backend_failed", error = ?error, "backend failed");
    }
    result
}

async fn run() -> AppResult<()> {
    let (mut interrupt, mut terminate) = (|| -> std::io::Result<_> {
        Ok((signal(SignalKind::interrupt())?, signal(SignalKind::terminate())?))
    })().inspect_err(|error| {
        tracing::error!(event = "startup_failed", operation = "InstallSignalHandlers", error = ?error, "could not install shutdown handlers");
    })?;
    let handoff = Arc::new(Notify::new());
    let (service, mut actor) = GreeterService::new(Arc::clone(&handoff));
    let connection = match async {
        Builder::session()?
            .name(BUS_NAME)?
            .serve_at(OBJECT_PATH, service)?
            .build()
            .await
    }
    .await
    {
        Ok(connection) => connection,
        Err(error) => {
            tracing::error!(error = ?error, event = "startup_failed", "could not start D-Bus service");
            actor.stop();
            (&mut actor.task).await?;
            return Err(error.into());
        }
    };

    tracing::info!(
        bus_name = BUS_NAME,
        object_path = OBJECT_PATH,
        "D-Bus service ready"
    );
    tokio::select! {
        _ = interrupt.recv() => tracing::info!(reason = "SIGINT", "shutdown requested"),
        _ = terminate.recv() => tracing::info!(reason = "SIGTERM", "shutdown requested"),
        _ = handoff.notified() => {
            tracing::info!(reason = "handoff", "session reply dispatched; shutting down")
        }
        _ = connection.closed() => {
            actor.stop();
            (&mut actor.task).await?;
            return Err("greeter D-Bus connection closed".into());
        }
        result = &mut actor.task => {
            connection.close().await?;
            return match result {
                Ok(()) => Err("authentication actor stopped unexpectedly".into()),
                Err(error) => Err(error.into()),
            };
        }
    }
    // Stop accepting calls before cancelling the active protocol exchange.
    let close_result = connection.close().await;
    actor.stop();
    (&mut actor.task).await?;
    close_result?;
    tracing::info!("backend shutdown complete");
    Ok(())
}

fn init_tracing() -> AppResult<()> {
    let filter =
        EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("backend=info,warn"));
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .with_ansi(std::io::IsTerminal::is_terminal(&std::io::stdout()))
        .try_init()?;
    Ok(())
}
