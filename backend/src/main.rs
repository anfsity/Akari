mod greetd;
mod service;
mod session_catalog;
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

#[tokio::main]
async fn main() -> AppResult<()> {
    init_tracing()?;
    let result = run().await;
    if let Err(error) = &result {
        tracing::error!(error = ?error, "backend failed");
    }
    result
}

async fn run() -> AppResult<()> {
    let mut interrupt = signal(SignalKind::interrupt())?;
    let mut terminate = signal(SignalKind::terminate())?;
    let handoff = Arc::new(Notify::new());
    let (service, mut actor) = GreeterService::new(Arc::clone(&handoff));
    let connection_result = async {
        Builder::session()?
            .name(BUS_NAME)?
            .serve_at(OBJECT_PATH, service)?
            .build()
            .await
    }
    .await;
    let connection = match connection_result {
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
    let result: AppResult<()> = tokio::select! {
        _ = interrupt.recv() => { tracing::info!(reason = "SIGINT", "shutdown requested"); Ok(()) },
        _ = terminate.recv() => { tracing::info!(reason = "SIGTERM", "shutdown requested"); Ok(()) },
        _ = handoff.notified() => { tracing::info!(reason = "handoff", "session reply dispatched; shutting down"); Ok(()) },
        _ = connection.closed() => { Err("greeter D-Bus connection closed".into()) },
        result = &mut actor.task => {
            connection.close().await?;
            return match result {
                Ok(()) => Err("authentication actor stopped unexpectedly".into()),
                Err(error) => Err(error.into()),
            };
        },
    };
    // Stop accepting calls before cancelling the active protocol exchange.
    let close_result = connection.close().await;
    actor.stop();
    (&mut actor.task).await?;
    close_result?;
    tracing::info!("backend shutdown complete");
    result
}

fn init_tracing() -> AppResult<()> {
    let filter =
        EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("backend=info,warn"));
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .try_init()?;
    Ok(())
}
