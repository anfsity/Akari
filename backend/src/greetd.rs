//! Client-side greetd protocol transport.
//!
//! Requests and responses use greetd's native-endian four-byte length prefix
//! followed by UTF-8 JSON. The real transport keeps credential-bearing buffers
//! in [`zeroize::Zeroizing`] storage, while the mock transport provides a
//! deterministic authentication flow for local and D-Bus integration tests.

use std::{env, io, path::Path, time::Duration};

use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::UnixStream,
    time::{error::Elapsed, timeout},
};
use tokio_util::sync::CancellationToken;
use zeroize::Zeroizing;

const MAX_FRAME_SIZE: usize = 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);

/// Errors produced while connecting to greetd or exchanging one framed request.
#[derive(Debug, Error)]
pub enum GreetdError {
    #[error("GREETD_SOCK is not set")]
    #[cfg_attr(feature = "mock", allow(dead_code))]
    SocketNotConfigured,
    #[error("could not connect to greetd")]
    #[cfg_attr(feature = "mock", allow(dead_code))]
    Connect(#[source] io::Error),
    #[error("could not encode greetd request")]
    Encode(#[source] serde_json::Error),
    #[error("greetd request is too large")]
    RequestTooLarge,
    #[error("greetd socket I/O failed")]
    Io(#[source] io::Error),
    #[error("greetd request timed out")]
    Timeout,
    #[error("greetd request was cancelled")]
    Cancelled,
    #[error("greetd response frame is too large")]
    ResponseTooLarge,
    #[error("greetd response was truncated")]
    ResponseTruncated,
    #[error("greetd response was malformed")]
    Decode(#[source] serde_json::Error),
    #[error("unexpected greetd response: {0}")]
    UnexpectedResponse(String),
}

/// Responses defined by greetd's authentication and session protocol.
#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub enum GreetdResponse {
    /// The requested operation completed successfully.
    #[serde(rename = "success")]
    Success,
    /// greetd rejected the operation and supplied a description.
    #[serde(rename = "error")]
    Error {
        error_type: String,
        description: String,
    },
    /// PAM requested a prompt or emitted an informational message.
    #[serde(rename = "auth_message")]
    AuthMessage {
        auth_message_type: String,
        auth_message: String,
    },
}

/// Selects the real greetd socket or the deterministic local mock.
#[derive(Debug)]
pub enum GreetdTransport {
    #[cfg_attr(feature = "mock", allow(dead_code))]
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
            Self::Real(client) => {
                GreetdClientApi::create_session(client, username, cancellation).await
            }
            #[cfg(feature = "mock")]
            Self::Mock(client) => {
                GreetdClientApi::create_session(client, username, cancellation).await
            }
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
            Self::Real(client) => {
                GreetdClientApi::post_auth_message_response(client, response, cancellation).await
            }
            #[cfg(feature = "mock")]
            Self::Mock(client) => {
                GreetdClientApi::post_auth_message_response(client, response, cancellation).await
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
            Self::Real(client) => {
                GreetdClientApi::start_session(client, cmd, env, cancellation).await
            }
            #[cfg(feature = "mock")]
            Self::Mock(client) => {
                GreetdClientApi::start_session(client, cmd, env, cancellation).await
            }
        }
    }

    /// Cancels the current greetd authentication session.
    pub async fn cancel_session(
        &mut self,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        match self {
            Self::Real(client) => GreetdClientApi::cancel_session(client, cancellation).await,
            #[cfg(feature = "mock")]
            Self::Mock(client) => GreetdClientApi::cancel_session(client, cancellation).await,
        }
    }
}

#[derive(Debug, Serialize)]
struct CreateSessionRequest<'a> {
    #[serde(rename = "type")]
    kind: &'static str,
    username: &'a str,
}

#[derive(Debug, Serialize)]
struct AuthMessageResponseRequest<'a> {
    #[serde(rename = "type")]
    kind: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    response: Option<&'a str>,
}

#[derive(Debug, Serialize)]
struct StartSessionRequest<'a> {
    #[serde(rename = "type")]
    kind: &'static str,
    cmd: &'a [String],
    env: &'a [String],
}

#[derive(Debug, Serialize)]
struct CancelSessionRequest {
    #[serde(rename = "type")]
    kind: &'static str,
}

/// Methods shared by the real greetd client and the generated mock client.
#[cfg_attr(feature = "mock", mockall::automock)]
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

/// An established greetd Unix-socket connection.
#[derive(Debug)]
pub struct GreetdClient {
    stream: UnixStream,
}

#[cfg_attr(feature = "mock", allow(dead_code))]
impl GreetdClient {
    /// Connects to the socket named by `GREETD_SOCK`.
    pub async fn connect(cancellation: &CancellationToken) -> Result<Self, GreetdError> {
        let socket = env::var_os("GREETD_SOCK").ok_or(GreetdError::SocketNotConfigured)?;
        Self::connect_at(&socket, cancellation).await
    }

    /// Connects to an explicitly supplied greetd socket path.
    pub async fn connect_at(
        path: impl AsRef<Path>,
        cancellation: &CancellationToken,
    ) -> Result<Self, GreetdError> {
        let path = path.as_ref().to_owned();
        let stream = tokio::select! {
            _ = cancellation.cancelled() => return Err(GreetdError::Cancelled),
            result = timeout(REQUEST_TIMEOUT, UnixStream::connect(path)) => {
                result.map_err(|_| GreetdError::Timeout)?.map_err(GreetdError::Connect)?
            }
        };
        Ok(Self { stream })
    }

    /// Sends `create_session` and waits for its response.
    pub async fn create_session(
        &mut self,
        username: &str,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        self.request(
            &CreateSessionRequest {
                kind: "create_session",
                username,
            },
            cancellation,
        )
        .await
    }

    /// Sends `post_auth_message_response` and waits for its response.
    pub async fn post_auth_message_response(
        &mut self,
        response: Option<&str>,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        self.request(
            &AuthMessageResponseRequest {
                kind: "post_auth_message_response",
                response,
            },
            cancellation,
        )
        .await
    }

    /// Sends `start_session` with the command and environment chosen by the backend.
    pub async fn start_session(
        &mut self,
        cmd: &[String],
        env: &[String],
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        self.request(
            &StartSessionRequest {
                kind: "start_session",
                cmd,
                env,
            },
            cancellation,
        )
        .await
    }

    /// Sends `cancel_session` and waits for greetd's response.
    pub async fn cancel_session(
        &mut self,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        self.request(
            &CancelSessionRequest {
                kind: "cancel_session",
            },
            cancellation,
        )
        .await
    }

    /// Serializes, frames, writes, and reads one greetd request/response pair.
    ///
    /// The serialized request and complete frame are zeroized when their
    /// owners are dropped because authentication responses can be embedded in
    /// the request payload.
    async fn request<T>(
        &mut self,
        request: &T,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError>
    where
        T: Serialize,
    {
        let payload = Zeroizing::new(serde_json::to_vec(request).map_err(GreetdError::Encode)?);
        let frame = encode_frame(payload.as_slice(), GreetdError::RequestTooLarge)?;
        tokio::select! {
            _ = cancellation.cancelled() => return Err(GreetdError::Cancelled),
            result = timeout(REQUEST_TIMEOUT, self.stream.write_all(&frame)) => {
                result.map_err(|_| GreetdError::Timeout)?.map_err(GreetdError::Io)?;
            }
        }
        tokio::select! {
            _ = cancellation.cancelled() => return Err(GreetdError::Cancelled),
            result = timeout(REQUEST_TIMEOUT, self.stream.flush()) => {
                result.map_err(|_| GreetdError::Timeout)?.map_err(GreetdError::Io)?;
            }
        }

        self.read_response(cancellation).await
    }

    /// Reads and decodes one length-prefixed response frame.
    ///
    /// The frame length is checked before allocation, and each exact read is
    /// bounded by [`REQUEST_TIMEOUT`].
    async fn read_response(
        &mut self,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        let mut length_bytes = [0_u8; 4];
        read_exact_with_timeout(&mut self.stream, &mut length_bytes, cancellation).await?;

        let length = u32::from_ne_bytes(length_bytes) as usize;
        if length > MAX_FRAME_SIZE {
            return Err(GreetdError::ResponseTooLarge);
        }

        let mut payload = Zeroizing::new(vec![0_u8; length]);
        read_exact_with_timeout(&mut self.stream, payload.as_mut_slice(), cancellation).await?;

        serde_json::from_slice(payload.as_slice()).map_err(GreetdError::Decode)
    }
}

impl GreetdClientApi for GreetdClient {
    async fn create_session(
        &mut self,
        username: &str,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        GreetdClient::create_session(self, username, cancellation).await
    }

    #[allow(clippy::needless_lifetimes)]
    async fn post_auth_message_response<'a>(
        &mut self,
        response: Option<&'a str>,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        GreetdClient::post_auth_message_response(self, response, cancellation).await
    }

    async fn start_session(
        &mut self,
        cmd: &[String],
        env: &[String],
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        GreetdClient::start_session(self, cmd, env, cancellation).await
    }

    async fn cancel_session(
        &mut self,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        GreetdClient::cancel_session(self, cancellation).await
    }
}

/// Adds greetd's native-endian length prefix to a JSON payload.
///
/// The caller supplies the request-specific oversize error so request and
/// response validation can report the correct direction of failure.
fn encode_frame(payload: &[u8], too_large: GreetdError) -> Result<Zeroizing<Vec<u8>>, GreetdError> {
    if payload.len() > MAX_FRAME_SIZE {
        return Err(too_large);
    }
    let length = u32::try_from(payload.len()).map_err(|_| GreetdError::RequestTooLarge)?;
    let mut frame = Zeroizing::new(Vec::with_capacity(4 + payload.len()));
    frame.extend_from_slice(&length.to_ne_bytes());
    frame.extend_from_slice(payload);
    Ok(frame)
}

#[cfg(feature = "mock")]
impl MockGreetdClientApi {
    fn configured() -> Self {
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

/// Performs one exact socket read with the protocol timeout and maps EOF to a
/// truncated-response error.
async fn read_exact_with_timeout(
    stream: &mut UnixStream,
    buffer: &mut [u8],
    cancellation: &CancellationToken,
) -> Result<(), GreetdError> {
    tokio::select! {
        _ = cancellation.cancelled() => Err(GreetdError::Cancelled),
        result = timeout(REQUEST_TIMEOUT, stream.read_exact(buffer)) => match result {
            Ok(Ok(_)) => Ok(()),
            Ok(Err(error)) if error.kind() == io::ErrorKind::UnexpectedEof => {
                Err(GreetdError::ResponseTruncated)
            }
            Ok(Err(error)) => Err(GreetdError::Io(error)),
            Err(Elapsed { .. }) => Err(GreetdError::Timeout),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::{
        path::PathBuf,
        time::{SystemTime, UNIX_EPOCH},
    };

    use serde_json::Value;
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::UnixListener,
    };

    use super::{AuthMessageResponseRequest, GreetdClient, GreetdResponse, encode_frame};

    use tokio_util::sync::CancellationToken;

    #[cfg(feature = "mock")]
    use super::GreetdTransport;

    #[test]
    fn encodes_native_endian_length_prefixed_json() {
        let payload = serde_json::to_vec(&serde_json::json!({
            "type": "create_session",
            "username": "alice"
        }))
        .unwrap();
        let frame = encode_frame(&payload, super::GreetdError::RequestTooLarge).unwrap();
        assert_eq!(
            u32::from_ne_bytes(frame[..4].try_into().unwrap()) as usize,
            payload.len()
        );
        assert_eq!(&frame[4..], payload.as_slice());
    }

    #[test]
    fn omits_response_for_informational_messages() {
        let request = AuthMessageResponseRequest {
            kind: "post_auth_message_response",
            response: None,
        };
        let payload = serde_json::to_vec(&request).unwrap();
        let value: Value = serde_json::from_slice(&payload).unwrap();
        assert_eq!(value["type"], "post_auth_message_response");
        assert!(value.get("response").is_none());
    }

    #[cfg(feature = "mock")]
    #[tokio::test]
    async fn mockall_transport_follows_authentication_flow() {
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

    #[cfg(feature = "mock")]
    #[tokio::test]
    async fn mockall_transport_rejects_wrong_password() {
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

    #[tokio::test]
    async fn real_transport_exchanges_framed_requests_with_fake_greetd() {
        let socket = test_socket_path();
        let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.expect("client should connect");

            let create = read_request(&mut stream).await;
            assert_eq!(create["type"], "create_session");
            assert_eq!(create["username"], "alice");
            write_response(
                &mut stream,
                serde_json::json!({
                    "type": "auth_message",
                    "auth_message_type": "secret",
                    "auth_message": "Password: "
                }),
            )
            .await;

            let response = read_request(&mut stream).await;
            assert_eq!(response["type"], "post_auth_message_response");
            assert_eq!(response["response"], "password");
            write_response(
                &mut stream,
                serde_json::json!({
                    "type": "auth_message",
                    "auth_message_type": "info",
                    "auth_message": "Authentication successful."
                }),
            )
            .await;

            let automatic_response = read_request(&mut stream).await;
            assert_eq!(automatic_response["type"], "post_auth_message_response");
            assert!(automatic_response.get("response").is_none());
            write_response(&mut stream, serde_json::json!({"type": "success"})).await;

            let start = read_request(&mut stream).await;
            assert_eq!(start["type"], "start_session");
            assert_eq!(start["cmd"], serde_json::json!(["/bin/test-session"]));
            assert_eq!(start["env"], serde_json::json!(["TEST_MODE=1"]));
            write_response(&mut stream, serde_json::json!({"type": "success"})).await;
        });

        let cancellation = CancellationToken::new();
        let mut client = GreetdClient::connect_at(&socket, &cancellation)
            .await
            .expect("real client should connect to fake greetd");
        assert!(matches!(
            client.create_session("alice", &cancellation).await,
            Ok(GreetdResponse::AuthMessage { .. })
        ));
        assert!(matches!(
            client
                .post_auth_message_response(Some("password"), &cancellation)
                .await,
            Ok(GreetdResponse::AuthMessage { .. })
        ));
        assert!(matches!(
            client.post_auth_message_response(None, &cancellation).await,
            Ok(GreetdResponse::Success)
        ));
        assert!(matches!(
            client
                .start_session(
                    &["/bin/test-session".to_owned()],
                    &["TEST_MODE=1".to_owned()],
                    &cancellation,
                )
                .await,
            Ok(GreetdResponse::Success)
        ));

        server.await.expect("fake greetd should finish");
        let _ = std::fs::remove_file(socket);
    }

    fn test_socket_path() -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should be valid")
            .as_nanos();
        std::env::temp_dir().join(format!(
            "mozais-greetd-test-{}-{nonce}.sock",
            std::process::id()
        ))
    }

    async fn read_request(stream: &mut tokio::net::UnixStream) -> Value {
        let mut length = [0_u8; 4];
        stream.read_exact(&mut length).await.unwrap();
        let mut payload = vec![0_u8; u32::from_ne_bytes(length) as usize];
        stream.read_exact(&mut payload).await.unwrap();
        serde_json::from_slice(&payload).unwrap()
    }

    async fn write_response(stream: &mut tokio::net::UnixStream, response: Value) {
        let payload = serde_json::to_vec(&response).unwrap();
        let frame = encode_frame(&payload, super::GreetdError::RequestTooLarge).unwrap();
        stream.write_all(&frame).await.unwrap();
        stream.flush().await.unwrap();
    }
}
