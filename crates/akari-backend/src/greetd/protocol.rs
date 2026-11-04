//! Wire messages and errors shared by real and mock greetd transports.

use std::io;

use serde::Deserialize;
#[cfg(any(not(feature = "mock"), test))]
use serde::Serialize;
use thiserror::Error;

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

#[cfg(any(not(feature = "mock"), test))]
#[derive(Debug, Serialize)]
pub(super) struct CreateSessionRequest<'a> {
    #[serde(rename = "type")]
    pub(super) kind: &'static str,
    pub(super) username: &'a str,
}

#[cfg(any(not(feature = "mock"), test))]
#[derive(Debug, Serialize)]
pub(super) struct AuthMessageResponseRequest<'a> {
    #[serde(rename = "type")]
    pub(super) kind: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) response: Option<&'a str>,
}

#[cfg(any(not(feature = "mock"), test))]
#[derive(Debug, Serialize)]
pub(super) struct StartSessionRequest<'a> {
    #[serde(rename = "type")]
    pub(super) kind: &'static str,
    pub(super) cmd: [String; 1],
    pub(super) env: &'a [String],
}

#[cfg(any(not(feature = "mock"), test))]
#[derive(Debug, Serialize)]
pub(super) struct CancelSessionRequest {
    #[serde(rename = "type")]
    pub(super) kind: &'static str,
}
