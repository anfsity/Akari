#![cfg(not(feature = "mock"))]

use std::{
    path::PathBuf,
    process::{Child, Command, Stdio},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

static TEST_LOCK: std::sync::OnceLock<tokio::sync::Mutex<()>> = std::sync::OnceLock::new();

use serde_json::Value;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{UnixListener, UnixStream},
    time::sleep,
};
use zbus::Proxy;

#[tokio::test]
async fn auth_roundtrip() {
    let _guard = lock().lock().await;
    let socket = socket_path();
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = tokio::spawn(fake_auth(listener));
    let mut backend = start_backend(&socket);

    let connection = connect_backend().await;
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

#[tokio::test]
async fn blank_username_is_rejected() {
    let _guard = lock().lock().await;
    let socket = socket_path();
    let mut backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;

    let result: zbus::Result<String> = proxy.call("BeginAuthentication", &("   ",)).await;

    assert!(result.is_err());
    stop_backend(&mut backend);
}

#[tokio::test]
async fn wrong_password_sets_failed_state() {
    let _guard = lock().lock().await;
    let socket = socket_path();
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = tokio::spawn(fake_bad_password(listener));
    let mut backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;

    let attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .expect("begin authentication should succeed");
    let state: (String, String) = proxy
        .call("GetState", &())
        .await
        .expect("state query should succeed");
    assert_eq!(state.0, "WaitingForInput");

    let result: zbus::Result<()> = proxy.call("Respond", &(attempt_id, "wrong")).await;
    assert!(result.is_err());

    let state: (String, String) = proxy
        .call("GetState", &())
        .await
        .expect("failed state query should succeed");
    assert_eq!(
        state,
        (
            "Failed".to_owned(),
            "auth_error: authentication failed".to_owned(),
        )
    );

    server.await.expect("fake greetd should finish");
    stop_backend(&mut backend);
    let _ = std::fs::remove_file(socket);
}

#[tokio::test]
async fn stale_attempt() {
    let _guard = lock().lock().await;
    let socket = socket_path();
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = tokio::spawn(fake_auth(listener));
    let mut backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;

    let _attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    let result: zbus::Result<()> = proxy.call("Respond", &("attempt-stale", "password")).await;

    assert!(result.is_err());
    stop_backend(&mut backend);
    server.abort();
    let _ = std::fs::remove_file(socket);
}

#[tokio::test]
async fn respond_early() {
    let _guard = lock().lock().await;
    let socket = socket_path();
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = tokio::spawn(fake_delayed_prompt(listener));
    let mut backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;

    let begin_connection = zbus::Connection::session().await.unwrap();
    let begin = tokio::spawn(async move {
        let attempt_proxy = make_proxy(&begin_connection).await;
        attempt_proxy
            .call::<_, _, String>("BeginAuthentication", &("alice",))
            .await
    });
    sleep(Duration::from_millis(20)).await;
    let result: zbus::Result<()> = proxy.call("Respond", &("attempt-stale", "password")).await;

    assert!(result.is_err());
    let _ = begin.await.unwrap();
    stop_backend(&mut backend);
    server.await.unwrap();
    let _ = std::fs::remove_file(socket);
}

#[tokio::test]
async fn bad_session() {
    let _guard = lock().lock().await;
    let socket = socket_path();
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = tokio::spawn(fake_auth(listener));
    let mut backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;

    let attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    proxy
        .call::<_, _, ()>("Respond", &(attempt_id.clone(), "password"))
        .await
        .unwrap();
    let result: zbus::Result<()> = proxy
        .call("StartSession", &(attempt_id, "wayland:missing"))
        .await;

    assert!(result.is_err());
    let state: (String, String) = proxy.call("GetState", &()).await.unwrap();
    assert_eq!(state.0, "Authenticated");

    server.await.unwrap();
    stop_backend(&mut backend);
    let _ = std::fs::remove_file(socket);
}

#[tokio::test]
async fn cancel_to_idle() {
    let _guard = lock().lock().await;
    let socket = socket_path();
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = tokio::spawn(fake_cancel(listener));
    let mut backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;

    let attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    let result: zbus::Result<()> = proxy.call("Cancel", &(attempt_id,)).await;
    assert!(result.is_ok());

    let state: (String, String) = proxy.call("GetState", &()).await.unwrap();
    assert_eq!(state.0, "Idle");
    server.await.unwrap();
    stop_backend(&mut backend);
    let _ = std::fs::remove_file(socket);
}

#[tokio::test]
async fn bad_power_action() {
    let _guard = lock().lock().await;
    let socket = socket_path();
    let mut backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;

    let result: zbus::Result<()> = proxy.call("PowerAction", &("Shutdown",)).await;

    assert!(result.is_err());
    stop_backend(&mut backend);
}

#[tokio::test]
async fn start_session() {
    let _guard = lock().lock().await;
    let socket = socket_path();
    let session_root = temp_dir("sessions");
    write_session(&session_root, "test.desktop", "Test");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = tokio::spawn(fake_start(listener, false));
    let mut backend = start_backend_for_sessions(&socket, &session_root);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;

    let attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    proxy
        .call::<_, _, ()>("Respond", &(attempt_id.clone(), "password"))
        .await
        .unwrap();
    proxy
        .call::<_, _, ()>("StartSession", &(attempt_id, "wayland:test"))
        .await
        .unwrap();

    let state: (String, String) = proxy.call("GetState", &()).await.unwrap();
    assert_eq!(state.0, "HandingOff");
    server.await.unwrap();
    stop_backend(&mut backend);
    remove_dir(session_root);
    let _ = std::fs::remove_file(socket);
}

#[tokio::test]
async fn start_session_fails() {
    let _guard = lock().lock().await;
    let socket = socket_path();
    let session_root = temp_dir("sessions-fail");
    write_session(&session_root, "test.desktop", "Test");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = tokio::spawn(fake_start(listener, true));
    let mut backend = start_backend_for_sessions(&socket, &session_root);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;

    let attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    proxy
        .call::<_, _, ()>("Respond", &(attempt_id.clone(), "password"))
        .await
        .unwrap();
    let result: zbus::Result<()> = proxy
        .call("StartSession", &(attempt_id, "wayland:test"))
        .await;
    assert!(result.is_err());

    let state: (String, String) = proxy.call("GetState", &()).await.unwrap();
    assert_eq!(
        state,
        ("Failed".to_owned(), "start_error: cannot start".to_owned())
    );
    server.await.unwrap();
    stop_backend(&mut backend);
    remove_dir(session_root);
    let _ = std::fs::remove_file(socket);
}

async fn fake_auth(listener: UnixListener) {
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

async fn fake_bad_password(listener: UnixListener) {
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
    assert_eq!(password["response"], "wrong");
    write_response(
        &mut stream,
        serde_json::json!({
            "type": "error",
            "error_type": "auth_error",
            "description": "authentication failed"
        }),
    )
    .await;
}

async fn fake_delayed_prompt(listener: UnixListener) {
    let (mut stream, _) = listener.accept().await.expect("backend should connect");
    let create = read_request(&mut stream).await;
    assert_eq!(create["type"], "create_session");
    sleep(Duration::from_millis(100)).await;
    write_response(
        &mut stream,
        serde_json::json!({
            "type": "auth_message",
            "auth_message_type": "secret",
            "auth_message": "Password: "
        }),
    )
    .await;
}

async fn fake_cancel(listener: UnixListener) {
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

    let cancel = read_request(&mut stream).await;
    assert_eq!(cancel["type"], "cancel_session");
    write_response(&mut stream, serde_json::json!({ "type": "success" })).await;
}

async fn fake_start(listener: UnixListener, fail_start: bool) {
    let (mut stream, _) = listener.accept().await.expect("backend should connect");
    let _ = read_request(&mut stream).await;
    write_response(
        &mut stream,
        serde_json::json!({
            "type": "auth_message",
            "auth_message_type": "secret",
            "auth_message": "Password: "
        }),
    )
    .await;
    let _ = read_request(&mut stream).await;
    write_response(
        &mut stream,
        serde_json::json!({
            "type": "auth_message",
            "auth_message_type": "info",
            "auth_message": "ok"
        }),
    )
    .await;
    let automatic = read_request(&mut stream).await;
    assert_eq!(automatic["type"], "post_auth_message_response");
    assert!(automatic.get("response").is_none());
    write_response(&mut stream, serde_json::json!({ "type": "success" })).await;
    let start = read_request(&mut stream).await;
    assert_eq!(start["type"], "start_session");
    if fail_start {
        write_response(
            &mut stream,
            serde_json::json!({
                "type": "error",
                "error_type": "start_error",
                "description": "cannot start"
            }),
        )
        .await;
    } else {
        write_response(&mut stream, serde_json::json!({ "type": "success" })).await;
    }
}

async fn connect_backend() -> zbus::Connection {
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

async fn make_proxy(connection: &zbus::Connection) -> zbus::Proxy<'_> {
    Proxy::new(
        connection,
        "io.mozais.Greeter",
        "/io/mozais/Greeter",
        "io.mozais.Greeter1",
    )
    .await
    .expect("backend proxy should be available")
}

fn lock() -> &'static tokio::sync::Mutex<()> {
    TEST_LOCK.get_or_init(|| tokio::sync::Mutex::new(()))
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

fn start_backend_for_sessions(socket: &PathBuf, session_root: &PathBuf) -> Child {
    Command::new(env!("CARGO_BIN_EXE_backend"))
        .env("GREETD_SOCK", socket)
        .env("MOZAIS_WAYLAND_SESSIONS", session_root)
        .env("MOZAIS_X11_SESSIONS", "/mozais/missing-x11")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("backend process should start")
}

fn temp_dir(label: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("mozais-{label}-{}", std::process::id()));
    std::fs::create_dir_all(&path).unwrap();
    path
}

fn write_session(root: &PathBuf, name: &str, display_name: &str) {
    std::fs::write(
        root.join(name),
        format!(
            "[Desktop Entry]\nType=Application\nName={display_name}\nExec=/usr/bin/true\nDesktopNames=test\n"
        ),
    )
    .unwrap();
}

fn remove_dir(path: PathBuf) {
    let _ = std::fs::remove_dir_all(path);
}

fn stop_backend(backend: &mut Child) {
    let _ = backend.kill();
    let _ = backend.wait();
}

fn socket_path() -> PathBuf {
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
