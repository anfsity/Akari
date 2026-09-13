mod greetd;
mod service;
mod session_catalog;
mod state;
mod users;

use std::error::Error;

use service::{BUS_NAME, GreeterService, OBJECT_PATH};
use std::sync::Arc;

use tokio::{signal, sync::Notify};
use tracing_subscriber::EnvFilter;
use zbus::connection::Builder;

type AppResult<T> = Result<T, Box<dyn Error + Send + Sync>>;

#[tokio::main]
async fn main() -> AppResult<()> {
    init_tracing()?;

    let handoff = Arc::new(Notify::new());
    let _connection = Builder::session()?
        .name(BUS_NAME)?
        .serve_at(OBJECT_PATH, GreeterService::new(Arc::clone(&handoff)))?
        .build()
        .await?;

    tracing::info!(
        bus_name = BUS_NAME,
        object_path = OBJECT_PATH,
        "D-Bus service ready"
    );

    tokio::select! {
        result = signal::ctrl_c() => result?,
        _ = handoff.notified() => {
            tracing::info!("session handoff requested");
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        },
    }
    tracing::info!("shutting down");

    Ok(())
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
