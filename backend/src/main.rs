mod dbus_service;

use std::error::Error;

use dbus_service::{BUS_NAME, GreeterService, OBJECT_PATH};
use tokio::signal;
use tracing_subscriber::EnvFilter;
use zbus::connection::Builder;

type AppResult<T> = Result<T, Box<dyn Error + Send + Sync>>;

#[tokio::main]
async fn main() -> AppResult<()> {
    init_tracing()?;

    let _connection = Builder::session()?
        .name(BUS_NAME)?
        .serve_at(OBJECT_PATH, GreeterService::default())?
        .build()
        .await?;

    tracing::info!(
        bus_name = BUS_NAME,
        object_path = OBJECT_PATH,
        "D-Bus service ready"
    );

    signal::ctrl_c().await?;
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
