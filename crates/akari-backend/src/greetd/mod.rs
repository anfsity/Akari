//! Client-side greetd protocol transport.
//!
//! Requests and responses use greetd's native-endian four-byte length prefix
//! followed by UTF-8 JSON. The real transport keeps credential-bearing buffers
//! in [`zeroize::Zeroizing`] storage, while the mock transport provides a
//! deterministic authentication flow for local and D-Bus integration tests.

#[cfg(feature = "mock")]
mod mock;
mod protocol;
#[cfg(any(not(feature = "mock"), test))]
mod transport;

use tokio_util::sync::CancellationToken;

#[cfg(feature = "mock")]
use mock::{GreetdClientApi, MockGreetdClientApi};
pub use protocol::{GreetdError, GreetdResponse};
#[cfg(not(feature = "mock"))]
use transport::GreetdClient;

/// Selects the real greetd socket or the deterministic local mock.
#[derive(Debug)]
pub enum GreetdTransport {
    #[cfg(not(feature = "mock"))]
    Real(GreetdClient),
    #[cfg(feature = "mock")]
    Mock(MockGreetdClientApi),
}

impl GreetdTransport {
    /// Connects to the configured transport.
    ///
    /// The mock implementation is compiled only with the `mock` feature;
    /// production builds therefore always use `GREETD_SOCK`.
    pub async fn connect(_cancellation: &CancellationToken) -> Result<Self, GreetdError> {
        #[cfg(feature = "mock")]
        {
            Ok(Self::Mock(MockGreetdClientApi::configured()))
        }

        #[cfg(not(feature = "mock"))]
        {
            Ok(Self::Real(GreetdClient::connect(_cancellation).await?))
        }
    }

    /// Starts a greetd authentication session for `username`.
    pub async fn create_session(
        &mut self,
        username: &str,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        match self {
            #[cfg(not(feature = "mock"))]
            Self::Real(client) => client.create_session(username, cancellation).await,
            #[cfg(feature = "mock")]
            Self::Mock(client) => client.create_session(username, cancellation).await,
        }
    }

    /// Submits an answer to the current greetd authentication message.
    ///
    /// `None` is used for informational and error messages, for which greetd
    /// expects an automatic empty response rather than UI input.
    pub async fn post_auth_message_response(
        &mut self,
        response: Option<&str>,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        match self {
            #[cfg(not(feature = "mock"))]
            Self::Real(client) => {
                client
                    .post_auth_message_response(response, cancellation)
                    .await
            }
            #[cfg(feature = "mock")]
            Self::Mock(client) => {
                client
                    .post_auth_message_response(response, cancellation)
                    .await
            }
        }
    }

    /// Requests greetd to launch the backend-validated session command.
    pub async fn start_session(
        &mut self,
        cmd: &[String],
        env: &[String],
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        match self {
            #[cfg(not(feature = "mock"))]
            Self::Real(client) => client.start_session(cmd, env, cancellation).await,
            #[cfg(feature = "mock")]
            Self::Mock(client) => client.start_session(cmd, env, cancellation).await,
        }
    }

    /// Cancels the current greetd authentication session.
    pub async fn cancel_session(
        &mut self,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        match self {
            #[cfg(not(feature = "mock"))]
            Self::Real(client) => client.cancel_session(cancellation).await,
            #[cfg(feature = "mock")]
            Self::Mock(client) => client.cancel_session(cancellation).await,
        }
    }
}
