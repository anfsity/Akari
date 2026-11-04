//! Deterministic greetd implementation compiled only for local mock builds.

use tokio_util::sync::CancellationToken;

use super::{GreetdError, GreetdResponse};

/// Signature used to generate the mock greetd transport in `mock` builds.
#[mockall::automock]
pub(crate) trait GreetdClientApi {
    async fn create_session(
        &mut self,
        username: &str,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError>;

    // mockall requires an explicit lifetime for this borrowed optional argument.
    #[allow(clippy::needless_lifetimes)]
    async fn post_auth_message_response<'a>(
        &mut self,
        response: Option<&'a str>,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError>;

    async fn start_session(
        &mut self,
        cmd: &[String],
        env: &[String],
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError>;

    async fn cancel_session(
        &mut self,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError>;
}

impl MockGreetdClientApi {
    pub(super) fn configured() -> Self {
        use mockall::Sequence;

        let mut mock = Self::new();
        let mut sequence = Sequence::new();

        mock.expect_create_session()
            .times(..=1)
            .in_sequence(&mut sequence)
            .returning(|_, cancellation| {
                if cancellation.is_cancelled() {
                    return Err(GreetdError::Cancelled);
                }
                Ok(GreetdResponse::AuthMessage {
                    auth_message_type: "secret".to_owned(),
                    auth_message: "Password: ".to_owned(),
                })
            });

        mock.expect_post_auth_message_response()
            .withf(|response, _| *response == Some("password"))
            .times(..=1)
            .in_sequence(&mut sequence)
            .returning(|_, cancellation| {
                if cancellation.is_cancelled() {
                    return Err(GreetdError::Cancelled);
                }
                Ok(GreetdResponse::AuthMessage {
                    auth_message_type: "info".to_owned(),
                    auth_message: "Authentication successful.".to_owned(),
                })
            });

        mock.expect_post_auth_message_response()
            .withf(|response, _| response.is_none())
            .times(..=1)
            .in_sequence(&mut sequence)
            .returning(|_, cancellation| {
                if cancellation.is_cancelled() {
                    return Err(GreetdError::Cancelled);
                }
                Ok(GreetdResponse::Success)
            });

        mock.expect_post_auth_message_response()
            .withf(|response, _| response.is_some() && *response != Some("password"))
            .returning(|_, cancellation| {
                if cancellation.is_cancelled() {
                    return Err(GreetdError::Cancelled);
                }
                Ok(GreetdResponse::Error {
                    error_type: "auth_error".to_owned(),
                    description: "authentication failed".to_owned(),
                })
            });

        mock.expect_start_session()
            .times(..=1)
            .returning(|_, _, cancellation| {
                if cancellation.is_cancelled() {
                    return Err(GreetdError::Cancelled);
                }
                Ok(GreetdResponse::Success)
            });

        mock.expect_cancel_session().returning(|cancellation| {
            if cancellation.is_cancelled() {
                return Err(GreetdError::Cancelled);
            }
            Ok(GreetdResponse::Success)
        });

        mock
    }
}

#[cfg(test)]
mod tests {
    use tokio_util::sync::CancellationToken;

    use super::super::{GreetdResponse, GreetdTransport};

    #[tokio::test]
    async fn mock_auth_flow() {
        let cancellation = CancellationToken::new();
        let mut transport = GreetdTransport::connect(&cancellation)
            .await
            .expect("mock transport should connect");

        assert!(matches!(
            transport.create_session("alice", &cancellation).await,
            Ok(GreetdResponse::AuthMessage {
                auth_message_type,
                auth_message
            }) if auth_message_type == "secret" && auth_message == "Password: "
        ));
        assert!(matches!(
            transport
                .post_auth_message_response(Some("password"), &cancellation)
                .await,
            Ok(GreetdResponse::AuthMessage {
                auth_message_type,
                auth_message
            }) if auth_message_type == "info" && auth_message == "Authentication successful."
        ));
        assert!(matches!(
            transport
                .post_auth_message_response(None, &cancellation)
                .await,
            Ok(GreetdResponse::Success)
        ));
        assert!(matches!(
            transport.start_session(&[], &[], &cancellation).await,
            Ok(GreetdResponse::Success)
        ));
    }

    #[tokio::test]
    async fn mock_rejects_password() {
        let cancellation = CancellationToken::new();
        let mut transport = GreetdTransport::connect(&cancellation)
            .await
            .expect("mock transport should connect");

        transport
            .create_session("alice", &cancellation)
            .await
            .expect("mock create_session should succeed");
        assert!(matches!(
            transport
                .post_auth_message_response(Some("incorrect"), &cancellation)
                .await,
            Ok(GreetdResponse::Error {
                error_type,
                description
            }) if error_type == "auth_error" && description == "authentication failed"
        ));
    }
}
