use std::{env, io, path::Path, time::Duration};

use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::UnixStream,
    time::{error::Elapsed, timeout},
};
use zeroize::Zeroizing;

const MAX_FRAME_SIZE: usize = 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Debug, Error)]
pub enum GreetdError {
    #[error("GREETD_SOCK is not set")]
    SocketNotConfigured,
    #[error("could not connect to greetd")]
    Connect(#[source] io::Error),
    #[error("could not encode greetd request")]
    Encode(#[source] serde_json::Error),
    #[error("greetd request is too large")]
    RequestTooLarge,
    #[error("greetd socket I/O failed")]
    Io(#[source] io::Error),
    #[error("greetd request timed out")]
    Timeout,
    #[error("greetd response frame is too large")]
    ResponseTooLarge,
    #[error("greetd response was truncated")]
    ResponseTruncated,
    #[error("greetd response was malformed")]
    Decode(#[source] serde_json::Error),
    #[error("unexpected greetd response: {0}")]
    UnexpectedResponse(String),
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub enum GreetdResponse {
    #[serde(rename = "success")]
    Success,
    #[serde(rename = "error")]
    Error {
        error_type: String,
        description: String,
    },
    #[serde(rename = "auth_message")]
    AuthMessage {
        auth_message_type: String,
        auth_message: String,
    },
}

#[derive(Debug)]
pub enum GreetdTransport {
    Real(GreetdClient),
    Mock(MockGreetdClient),
}

impl GreetdTransport {
    pub async fn connect() -> Result<Self, GreetdError> {
        if env::var("MOZAIS_BACKEND").as_deref() == Ok("mock") {
            return Ok(Self::Mock(MockGreetdClient::connect()));
        }

        Ok(Self::Real(GreetdClient::connect().await?))
    }

    pub async fn create_session(&mut self, username: &str) -> Result<GreetdResponse, GreetdError> {
        match self {
            Self::Real(client) => client.create_session(username).await,
            Self::Mock(client) => client.create_session(username).await,
        }
    }

    pub async fn post_auth_message_response(
        &mut self,
        response: Option<&str>,
    ) -> Result<GreetdResponse, GreetdError> {
        match self {
            Self::Real(client) => client.post_auth_message_response(response).await,
            Self::Mock(client) => client.post_auth_message_response(response).await,
        }
    }

    pub async fn start_session(
        &mut self,
        cmd: &[String],
        env: &[String],
    ) -> Result<GreetdResponse, GreetdError> {
        match self {
            Self::Real(client) => client.start_session(cmd, env).await,
            Self::Mock(client) => client.start_session(cmd, env).await,
        }
    }

    pub async fn cancel_session(&mut self) -> Result<GreetdResponse, GreetdError> {
        match self {
            Self::Real(client) => client.cancel_session().await,
            Self::Mock(client) => client.cancel_session().await,
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

#[derive(Debug)]
pub struct GreetdClient {
    stream: UnixStream,
}

impl GreetdClient {
    pub async fn connect() -> Result<Self, GreetdError> {
        let socket = env::var_os("GREETD_SOCK").ok_or(GreetdError::SocketNotConfigured)?;
        Self::connect_at(&socket).await
    }

    pub async fn connect_at(path: impl AsRef<Path>) -> Result<Self, GreetdError> {
        let stream = UnixStream::connect(path)
            .await
            .map_err(GreetdError::Connect)?;
        Ok(Self { stream })
    }

    pub async fn create_session(&mut self, username: &str) -> Result<GreetdResponse, GreetdError> {
        self.request(&CreateSessionRequest {
            kind: "create_session",
            username,
        })
        .await
    }

    pub async fn post_auth_message_response(
        &mut self,
        response: Option<&str>,
    ) -> Result<GreetdResponse, GreetdError> {
        self.request(&AuthMessageResponseRequest {
            kind: "post_auth_message_response",
            response,
        })
        .await
    }

    pub async fn start_session(
        &mut self,
        cmd: &[String],
        env: &[String],
    ) -> Result<GreetdResponse, GreetdError> {
        self.request(&StartSessionRequest {
            kind: "start_session",
            cmd,
            env,
        })
        .await
    }

    pub async fn cancel_session(&mut self) -> Result<GreetdResponse, GreetdError> {
        self.request(&CancelSessionRequest {
            kind: "cancel_session",
        })
        .await
    }

    async fn request<T>(&mut self, request: &T) -> Result<GreetdResponse, GreetdError>
    where
        T: Serialize,
    {
        let payload = Zeroizing::new(serde_json::to_vec(request).map_err(GreetdError::Encode)?);
        let frame = encode_frame(payload.as_slice(), GreetdError::RequestTooLarge)?;
        self.stream
            .write_all(&frame)
            .await
            .map_err(GreetdError::Io)?;
        self.stream.flush().await.map_err(GreetdError::Io)?;

        self.read_response().await
    }

    async fn read_response(&mut self) -> Result<GreetdResponse, GreetdError> {
        let mut length_bytes = [0_u8; 4];
        read_exact_with_timeout(&mut self.stream, &mut length_bytes).await?;

        let length = u32::from_ne_bytes(length_bytes) as usize;
        if length > MAX_FRAME_SIZE {
            return Err(GreetdError::ResponseTooLarge);
        }

        let mut payload = Zeroizing::new(vec![0_u8; length]);
        read_exact_with_timeout(&mut self.stream, payload.as_mut_slice()).await?;

        serde_json::from_slice(payload.as_slice()).map_err(GreetdError::Decode)
    }
}

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

#[derive(Debug)]
pub struct MockGreetdClient {
    phase: MockPhase,
}

#[derive(Debug, Eq, PartialEq)]
enum MockPhase {
    AwaitingPassword,
    AwaitingInformationalReply,
    Authenticated,
}

impl MockGreetdClient {
    fn connect() -> Self {
        Self {
            phase: MockPhase::AwaitingPassword,
        }
    }

    async fn create_session(&mut self, _username: &str) -> Result<GreetdResponse, GreetdError> {
        self.phase = MockPhase::AwaitingPassword;
        Ok(GreetdResponse::AuthMessage {
            auth_message_type: "secret".to_owned(),
            auth_message: "Password: ".to_owned(),
        })
    }

    async fn post_auth_message_response(
        &mut self,
        response: Option<&str>,
    ) -> Result<GreetdResponse, GreetdError> {
        match (&self.phase, response) {
            (MockPhase::AwaitingPassword, Some("password")) => {
                self.phase = MockPhase::AwaitingInformationalReply;
                Ok(GreetdResponse::AuthMessage {
                    auth_message_type: "info".to_owned(),
                    auth_message: "Authentication successful.".to_owned(),
                })
            }
            (MockPhase::AwaitingPassword, Some(_)) => Ok(GreetdResponse::Error {
                error_type: "auth_error".to_owned(),
                description: "authentication failed".to_owned(),
            }),
            (MockPhase::AwaitingInformationalReply, None) => {
                self.phase = MockPhase::Authenticated;
                Ok(GreetdResponse::Success)
            }
            _ => Ok(GreetdResponse::Error {
                error_type: "error".to_owned(),
                description: "mock authentication protocol is out of sequence".to_owned(),
            }),
        }
    }

    async fn start_session(
        &mut self,
        _cmd: &[String],
        _env: &[String],
    ) -> Result<GreetdResponse, GreetdError> {
        if self.phase == MockPhase::Authenticated {
            Ok(GreetdResponse::Success)
        } else {
            Ok(GreetdResponse::Error {
                error_type: "error".to_owned(),
                description: "mock session is not authenticated".to_owned(),
            })
        }
    }

    async fn cancel_session(&mut self) -> Result<GreetdResponse, GreetdError> {
        self.phase = MockPhase::AwaitingPassword;
        Ok(GreetdResponse::Success)
    }
}

async fn read_exact_with_timeout(
    stream: &mut UnixStream,
    buffer: &mut [u8],
) -> Result<(), GreetdError> {
    match timeout(REQUEST_TIMEOUT, stream.read_exact(buffer)).await {
        Ok(Ok(_)) => Ok(()),
        Ok(Err(error)) if error.kind() == io::ErrorKind::UnexpectedEof => {
            Err(GreetdError::ResponseTruncated)
        }
        Ok(Err(error)) => Err(GreetdError::Io(error)),
        Err(Elapsed { .. }) => Err(GreetdError::Timeout),
    }
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use super::{AuthMessageResponseRequest, encode_frame};

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
}
