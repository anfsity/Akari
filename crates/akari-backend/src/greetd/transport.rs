//! Unix socket ownership, bounded framing, and zeroized credential buffers.

use std::{env, io, path::Path, time::Duration};

use serde::Serialize;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::UnixStream,
    time::timeout,
};
use tokio_util::sync::CancellationToken;
use zeroize::Zeroizing;

use super::protocol::{
    AuthMessageResponseRequest, CancelSessionRequest, CreateSessionRequest, GreetdError,
    GreetdResponse, StartSessionRequest,
};

const MAX_FRAME_SIZE: usize = 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);

enum ResponseWait {
    Pam,
    Immediate,
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
            biased;
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
            ResponseWait::Pam,
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
            ResponseWait::Pam,
        )
        .await
    }

    /// Encodes argv for greetd's sh command line before sending `start_session`.
    pub async fn start_session(
        &mut self,
        cmd: &[String],
        env: &[String],
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        self.request(
            &StartSessionRequest {
                kind: "start_session",
                cmd: [encode_command(cmd)],
                env,
            },
            cancellation,
            ResponseWait::Immediate,
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
            ResponseWait::Immediate,
        )
        .await
    }

    /// Serializes, frames, writes, and reads one greetd request/response pair.
    ///
    /// The serialized request and complete frame are zeroized when their
    /// owners are dropped because authentication responses can be embedded in
    /// the request payload.
    /// Cancellation or timeout can interrupt a frame partway through I/O. The
    /// actor must discard this connection on those errors rather than reuse it
    /// for another request and risk pairing that request with an old response.
    async fn request<T>(
        &mut self,
        request: &T,
        cancellation: &CancellationToken,
        response_wait: ResponseWait,
    ) -> Result<GreetdResponse, GreetdError>
    where
        T: Serialize,
    {
        let payload = Zeroizing::new(serde_json::to_vec(request).map_err(GreetdError::Encode)?);
        let frame = encode_frame(payload.as_slice())?;
        tokio::select! {
            biased;
            _ = cancellation.cancelled() => return Err(GreetdError::Cancelled),
            result = timeout(REQUEST_TIMEOUT, async {
                self.stream.write_all(&frame).await?;
                self.stream.flush().await
            }) => {
                result.map_err(|_| GreetdError::Timeout)?.map_err(GreetdError::Io)?;
            }
        }

        match response_wait {
            ResponseWait::Pam => self.read_response(cancellation).await,
            ResponseWait::Immediate => timeout(REQUEST_TIMEOUT, self.read_response(cancellation))
                .await
                .map_err(|_| GreetdError::Timeout)?,
        }
    }

    /// Reads and decodes one length-prefixed response frame.
    ///
    /// PAM may wait for a camera or another external factor before producing a
    /// response. Wait cancellably for its first byte, then bound the remaining
    /// frame reads so an incomplete response cannot stall the conversation.
    async fn read_response(
        &mut self,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        let mut length_bytes = [0_u8; 4];
        read_exact(&mut self.stream, &mut length_bytes[..1], cancellation).await?;
        read_exact_with_timeout(&mut self.stream, &mut length_bytes[1..], cancellation).await?;

        let length = u32::from_ne_bytes(length_bytes) as usize;
        if length > MAX_FRAME_SIZE {
            return Err(GreetdError::ResponseTooLarge);
        }

        let mut payload = Zeroizing::new(vec![0_u8; length]);
        read_exact_with_timeout(&mut self.stream, payload.as_mut_slice(), cancellation).await?;

        serde_json::from_slice(payload.as_slice()).map_err(GreetdError::Decode)
    }
}

/// greetd joins `cmd` with spaces and runs it through sh. Quote each argument
/// at this protocol boundary so empty arguments and shell syntax remain data.
fn encode_command(arguments: &[String]) -> String {
    arguments
        .iter()
        .map(|argument| format!("'{}'", argument.replace('\'', "'\\''")))
        .collect::<Vec<_>>()
        .join(" ")
}

/// Adds greetd's native-endian length prefix to a request JSON payload.
fn encode_frame(payload: &[u8]) -> Result<Zeroizing<Vec<u8>>, GreetdError> {
    const _: () = assert!(MAX_FRAME_SIZE <= u32::MAX as usize);
    if payload.len() > MAX_FRAME_SIZE {
        return Err(GreetdError::RequestTooLarge);
    }
    let length = payload.len() as u32;
    let mut frame = Zeroizing::new(Vec::with_capacity(4 + payload.len()));
    frame.extend_from_slice(&length.to_ne_bytes());
    frame.extend_from_slice(payload);
    Ok(frame)
}

/// Performs one exact socket read with the protocol timeout and maps EOF to a
/// truncated-response error.
async fn read_exact_with_timeout(
    stream: &mut UnixStream,
    buffer: &mut [u8],
    cancellation: &CancellationToken,
) -> Result<(), GreetdError> {
    timeout(REQUEST_TIMEOUT, read_exact(stream, buffer, cancellation))
        .await
        .map_err(|_| GreetdError::Timeout)?
}

async fn read_exact(
    stream: &mut UnixStream,
    buffer: &mut [u8],
    cancellation: &CancellationToken,
) -> Result<(), GreetdError> {
    tokio::select! {
        biased;
        _ = cancellation.cancelled() => Err(GreetdError::Cancelled),
        result = stream.read_exact(buffer) => match result {
            Ok(_) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => {
                Err(GreetdError::ResponseTruncated)
            }
            Err(error) => Err(GreetdError::Io(error)),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::{
        path::PathBuf,
        process::Command,
        time::{Duration, SystemTime, UNIX_EPOCH},
    };

    use serde_json::Value;
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::{UnixListener, UnixStream},
    };

    use super::{
        AuthMessageResponseRequest, GreetdClient, GreetdError, GreetdResponse, MAX_FRAME_SIZE,
        encode_command, encode_frame,
    };

    use tokio_util::sync::CancellationToken;

    #[test]
    fn shell_handoff_preserves_literal_and_empty_arguments() {
        let arguments = [
            "/usr/bin/printf",
            "<%s>\\n",
            "",
            "中文 路径",
            "it's quoted",
            "$HOME `false` $(false); exit 99",
            "line\nbreak",
        ]
        .map(str::to_owned);
        let output = Command::new("/bin/sh")
            .args(["-c", &format!("exec {}", encode_command(&arguments))])
            .output()
            .unwrap();

        assert!(output.status.success());
        assert_eq!(
            String::from_utf8(output.stdout).unwrap(),
            "<>\n<中文 路径>\n<it's quoted>\n<$HOME `false` $(false); exit 99>\n<line\nbreak>\n"
        );
    }

    #[test]
    fn shell_handoff_preserves_sh_command_and_exit_status() {
        let arguments = ["/bin/sh", "-c", "exit 23"].map(str::to_owned);
        let status = Command::new("/bin/sh")
            .args(["-c", &format!("exec {}", encode_command(&arguments))])
            .status()
            .unwrap();

        assert_eq!(status.code(), Some(23));
    }

    #[test]
    fn encodes_frame() {
        let payload = serde_json::to_vec(&serde_json::json!({
            "type": "create_session",
            "username": "alice"
        }))
        .unwrap();
        let frame = encode_frame(&payload).unwrap();
        assert_eq!(
            u32::from_ne_bytes(frame[..4].try_into().unwrap()) as usize,
            payload.len()
        );
        assert_eq!(&frame[4..], payload.as_slice());
    }

    #[test]
    fn omits_response() {
        let request = AuthMessageResponseRequest {
            kind: "post_auth_message_response",
            response: None,
        };
        let payload = serde_json::to_vec(&request).unwrap();
        let value: Value = serde_json::from_slice(&payload).unwrap();
        assert_eq!(value["type"], "post_auth_message_response");
        assert!(value.get("response").is_none());
    }

    #[test]
    fn rejects_big_frame() {
        let payload = vec![0_u8; MAX_FRAME_SIZE + 1];

        assert!(matches!(
            encode_frame(&payload),
            Err(GreetdError::RequestTooLarge)
        ));
    }

    #[tokio::test]
    async fn cancelled_connect() {
        let cancellation = CancellationToken::new();
        cancellation.cancel();

        let result =
            GreetdClient::connect_at("/akari/path-that-does-not-exist.sock", &cancellation).await;

        assert!(result.is_err());
    }

    #[tokio::test]
    async fn rejects_truncated_response() {
        let socket = socket_path();
        let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let _ = read_request(&mut stream).await;
            stream.write_all(&4_u32.to_ne_bytes()).await.unwrap();
            stream.write_all(b"{}").await.unwrap();
        });

        let cancellation = CancellationToken::new();
        let mut client = GreetdClient::connect_at(&socket, &cancellation)
            .await
            .unwrap();
        let error = client
            .create_session("alice", &cancellation)
            .await
            .unwrap_err();

        assert!(matches!(error, GreetdError::ResponseTruncated));
        server.await.unwrap();
        let _ = std::fs::remove_file(socket);
    }

    #[tokio::test]
    async fn rejects_bad_response() {
        let socket = socket_path();
        let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let _ = read_request(&mut stream).await;
            write_raw(&mut stream, b"not-json").await;
        });

        let cancellation = CancellationToken::new();
        let mut client = GreetdClient::connect_at(&socket, &cancellation)
            .await
            .unwrap();
        let error = client
            .create_session("alice", &cancellation)
            .await
            .unwrap_err();

        assert!(matches!(error, GreetdError::Decode(_)));
        server.await.unwrap();
        let _ = std::fs::remove_file(socket);
    }

    #[tokio::test]
    async fn rejects_big_response() {
        let socket = socket_path();
        let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let _ = read_request(&mut stream).await;
            stream
                .write_all(&((MAX_FRAME_SIZE as u32) + 1).to_ne_bytes())
                .await
                .unwrap();
        });

        let cancellation = CancellationToken::new();
        let mut client = GreetdClient::connect_at(&socket, &cancellation)
            .await
            .unwrap();
        let error = client
            .create_session("alice", &cancellation)
            .await
            .unwrap_err();

        assert!(matches!(error, GreetdError::ResponseTooLarge));
        server.await.unwrap();
        let _ = std::fs::remove_file(socket);
    }

    #[tokio::test]
    async fn cancels_read() {
        let socket = socket_path();
        let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let _ = read_request(&mut stream).await;
            tokio::time::sleep(Duration::from_millis(100)).await;
        });

        let cancellation = CancellationToken::new();
        let mut client = GreetdClient::connect_at(&socket, &cancellation)
            .await
            .unwrap();
        let cancel = cancellation.clone();
        let task = tokio::spawn(async move { client.create_session("alice", &cancel).await });
        tokio::time::sleep(Duration::from_millis(10)).await;
        cancellation.cancel();
        let error = task.await.unwrap().unwrap_err();

        assert!(matches!(error, GreetdError::Cancelled));
        server.await.unwrap();
        let _ = std::fs::remove_file(socket);
    }

    #[tokio::test]
    async fn slow_pam_responses_preserve_password_fallback() {
        let (stream, mut server) = UnixStream::pair().unwrap();
        let request = tokio::spawn(async move {
            let mut client = GreetdClient { stream };
            let cancellation = CancellationToken::new();
            assert!(matches!(
                client.create_session("alice", &cancellation).await,
                Ok(GreetdResponse::AuthMessage { auth_message_type, .. })
                    if auth_message_type == "info"
            ));
            assert!(matches!(
                client.post_auth_message_response(None, &cancellation).await,
                Ok(GreetdResponse::AuthMessage { auth_message_type, .. })
                    if auth_message_type == "secret"
            ));
            assert!(matches!(
                client
                    .post_auth_message_response(Some("password"), &cancellation)
                    .await,
                Ok(GreetdResponse::Success)
            ));
        });
        for response in [
            serde_json::json!({
                "type": "auth_message", "auth_message_type": "info",
                "auth_message": "Attempting facial authentication"
            }),
            serde_json::json!({
                "type": "auth_message", "auth_message_type": "secret",
                "auth_message": "Password: "
            }),
            serde_json::json!({"type": "success"}),
        ] {
            let _ = read_request(&mut server).await;
            tokio::task::yield_now().await;
            tokio::time::pause();
            tokio::time::advance(Duration::from_secs(12)).await;
            tokio::task::yield_now().await;
            assert!(
                !request.is_finished(),
                "PAM must own its authentication deadline"
            );
            tokio::time::resume();
            write_response(&mut server, response).await;
        }
        request.await.unwrap();
    }

    #[tokio::test]
    async fn slow_pam_wait_remains_cancellable() {
        let (stream, mut server) = UnixStream::pair().unwrap();
        let cancellation = CancellationToken::new();
        let cancel = cancellation.clone();
        let request = tokio::spawn(async move {
            GreetdClient { stream }
                .create_session("alice", &cancel)
                .await
        });
        let _ = read_request(&mut server).await;
        tokio::task::yield_now().await;
        tokio::time::pause();
        tokio::time::advance(Duration::from_secs(12)).await;
        cancellation.cancel();
        assert!(matches!(
            request.await.unwrap(),
            Err(GreetdError::Cancelled)
        ));
    }

    #[tokio::test]
    async fn partial_response_frames_still_timeout() {
        for partial in [
            4_u32.to_ne_bytes()[..1].to_vec(),
            [4_u32.to_ne_bytes().as_slice(), b"{"].concat(),
        ] {
            let (stream, mut server) = UnixStream::pair().unwrap();
            let request = tokio::spawn(async move {
                GreetdClient { stream }
                    .create_session("alice", &CancellationToken::new())
                    .await
            });
            let _ = read_request(&mut server).await;
            server.write_all(&partial).await.unwrap();
            tokio::time::pause();
            assert!(matches!(request.await.unwrap(), Err(GreetdError::Timeout)));
            tokio::time::resume();
        }
    }

    #[tokio::test]
    async fn session_start_and_cancel_replies_still_timeout() {
        for start_session in [false, true] {
            let (stream, mut server) = UnixStream::pair().unwrap();
            let request = tokio::spawn(async move {
                let mut client = GreetdClient { stream };
                let cancellation = CancellationToken::new();
                if start_session {
                    client
                        .start_session(&["/bin/session".into()], &[], &cancellation)
                        .await
                } else {
                    client.cancel_session(&cancellation).await
                }
            });
            let _ = read_request(&mut server).await;
            tokio::time::pause();
            assert!(matches!(request.await.unwrap(), Err(GreetdError::Timeout)));
            tokio::time::resume();
        }
    }

    #[tokio::test]
    async fn decodes_error() {
        let socket = socket_path();
        let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let _ = read_request(&mut stream).await;
            write_response(
                &mut stream,
                serde_json::json!({
                    "type": "error",
                    "error_type": "auth_error",
                    "description": "denied"
                }),
            )
            .await;
        });

        let cancellation = CancellationToken::new();
        let mut client = GreetdClient::connect_at(&socket, &cancellation)
            .await
            .unwrap();
        assert!(matches!(
            client.create_session("alice", &cancellation).await,
            Ok(GreetdResponse::Error { error_type, description })
                if error_type == "auth_error" && description == "denied"
        ));

        server.await.unwrap();
        let _ = std::fs::remove_file(socket);
    }

    #[tokio::test]
    async fn cancel_roundtrip() {
        let socket = socket_path();
        let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let request = read_request(&mut stream).await;
            assert_eq!(request["type"], "cancel_session");
            write_response(&mut stream, serde_json::json!({"type": "success"})).await;
        });

        let cancellation = CancellationToken::new();
        let mut client = GreetdClient::connect_at(&socket, &cancellation)
            .await
            .unwrap();
        assert!(matches!(
            client.cancel_session(&cancellation).await,
            Ok(GreetdResponse::Success)
        ));

        server.await.unwrap();
        let _ = std::fs::remove_file(socket);
    }

    #[tokio::test]
    async fn real_roundtrip() {
        let socket = socket_path();
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
            assert_eq!(start["cmd"], serde_json::json!(["'/bin/test-session'"]));
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

    fn socket_path() -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should be valid")
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "akari-greetd-test-{}-{nonce}.sock",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        path
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
        let frame = encode_frame(&payload).unwrap();
        stream.write_all(&frame).await.unwrap();
        stream.flush().await.unwrap();
    }

    async fn write_raw(stream: &mut tokio::net::UnixStream, payload: &[u8]) {
        stream
            .write_all(&(payload.len() as u32).to_ne_bytes())
            .await
            .unwrap();
        stream.write_all(payload).await.unwrap();
        stream.flush().await.unwrap();
    }
}
