use std::sync::Arc;

use tokio::sync::RwLock;
use zbus::interface;

use crate::state::AuthStateMachine;

pub const BUS_NAME: &str = "io.mozais.Greeter";
pub const OBJECT_PATH: &str = "/io/mozais/Greeter";

#[derive(Debug, Default)]
pub struct GreeterService {
    state: Arc<RwLock<AuthStateMachine>>,
}

#[interface(name = "io.mozais.Greeter1")]
impl GreeterService {
    async fn get_state(&self) -> (String, String) {
        let state = self.state.read().await;
        (state.state().as_str().to_owned(), state.detail().to_owned())
    }
}
