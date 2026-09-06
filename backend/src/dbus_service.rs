use std::sync::Arc;

use tokio::sync::RwLock;
use zbus::{fdo, interface};

use crate::state::{AuthStateMachine, BeginAuthenticationError};

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

    async fn begin_authentication(&self, username: String) -> fdo::Result<String> {
        let mut state = self.state.write().await;
        state
            .begin_authentication(username)
            .map_err(map_begin_authentication_error)
    }
}

fn map_begin_authentication_error(error: BeginAuthenticationError) -> fdo::Error {
    let detail = error.to_string();

    match error {
        BeginAuthenticationError::EmptyUsername => fdo::Error::InvalidArgs(detail),
        BeginAuthenticationError::InvalidState(_)
        | BeginAuthenticationError::AttemptIdExhausted => fdo::Error::Failed(detail),
    }
}
