#![cfg(not(feature = "mock"))]

use std::{
    path::PathBuf,
    process::{Child, Command, Stdio},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use serde_json::Value;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{UnixListener, UnixStream},
    time::sleep,
};
use zbus::Proxy;

#[tokio::test]
async fn dbus_client_backend_and_greetd_socket_complete_authentication() {
    let socket = test_socket_path();
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = tokio::spawn(fake_greetd(listener));
    let mut backend = start_backend(&socket);

    let connection = connect_to_backend().await;
    let proxy = Proxy::new(
        &connection,
        "io.mozais.Greeter",
        "/io/mozais/Greeter",
        "io.mozais.Greeter1",
    )
    .await
    .expect("backend proxy should be available");

    let attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .expect("begin authentication should succeed");
    let state: (String, String) = proxy
        .call("GetState", &())
        .await
        .expect("state query should succeed");
    assert_eq!(state.0, "WaitingForInput");

    proxy
        .call::<_, _, ()>("Respond", &(attempt_id.clone(), "password"))
        .await
        .expect("password response should succeed");
    let state: (String, String) = proxy
        .call("GetState", &())
        .await
        .expect("state query should succeed");
    assert_eq!(state.0, "Authenticated");

    server.await.expect("fake greetd should finish");
    stop_backend(&mut backend);
    let _ = std::fs::remove_file(socket);
}

async fn fake_greetd(listener: UnixListener) {
    let (mut stream, _) = listener.accept().await.expect("backend should connect");

    let create = read_request(&mut stream).await;
    assert_eq!(create["type"], "create_session");
    write_response(
        &mut stream,
        serde_json::json!({
            "type": "auth_message",
            "auth_message_type": "secret",
            "auth_message": "Password: "
        }),
    )
    .await;

    let password = read_request(&mut stream).await;
    assert_eq!(password["type"], "post_auth_message_response");
    assert_eq!(password["response"], "password");
    write_response(
        &mut stream,
        serde_json::json!({
            "type": "auth_message",
            "auth_message_type": "info",
            "auth_message": "Authentication successful."
        }),
    )
    .await;

    let automatic = read_request(&mut stream).await;
    assert_eq!(automatic["type"], "post_auth_message_response");
    assert!(automatic.get("response").is_none());
    write_response(&mut stream, serde_json::json!({ "type": "success" })).await;
}

async fn connect_to_backend() -> zbus::Connection {
    for _ in 0..100 {
        if let Ok(connection) = zbus::Connection::session().await {
            if let Ok(proxy) = Proxy::new(
                &connection,
                "io.mozais.Greeter",
                "/io/mozais/Greeter",
                "io.mozais.Greeter1",
            )
            .await
            {
                if proxy
                    .call::<_, _, (String, String)>("GetState", &())
                    .await
                    .is_ok()
                {
                    return connection;
                }
            }
        }
        sleep(Duration::from_millis(20)).await;
    }
    panic!("backend did not appear on the session bus");
}

fn start_backend(socket: &PathBuf) -> Child {
    Command::new(env!("CARGO_BIN_EXE_backend"))
        .env("GREETD_SOCK", socket)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("backend process should start")
}

fn stop_backend(backend: &mut Child) {
    let _ = backend.kill();
    let _ = backend.wait();
}

fn test_socket_path() -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock should be valid")
        .as_nanos();
    std::env::temp_dir().join(format!(
        "mozais-greetd-dbus-test-{}-{nonce}.sock",
        std::process::id()
    ))
}

async fn read_request(stream: &mut UnixStream) -> Value {
    let mut length = [0_u8; 4];
    stream.read_exact(&mut length).await.unwrap();
    let mut payload = vec![0_u8; u32::from_ne_bytes(length) as usize];
    stream.read_exact(&mut payload).await.unwrap();
    serde_json::from_slice(&payload).unwrap()
}

async fn write_response(stream: &mut UnixStream, response: Value) {
    let payload = serde_json::to_vec(&response).unwrap();
    let length = (payload.len() as u32).to_ne_bytes();
    stream.write_all(&length).await.unwrap();
    stream.write_all(&payload).await.unwrap();
    stream.flush().await.unwrap();
}
