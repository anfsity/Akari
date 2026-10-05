#![cfg(not(feature = "mock"))]

use std::{
    io::{BufRead, BufReader},
    path::{Path, PathBuf},
    process::{Child, Command, ExitStatus, Stdio},
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
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_auth(listener));
    let backend = start_backend(&socket);

    let connection = connect_backend().await;
    let proxy = Proxy::new(
        &connection,
        "io.akari.Greeter",
        "/io/akari/Greeter",
        "io.akari.Greeter1",
    )
    .await
    .expect("backend proxy should be available");

    #[cfg(feature = "mock-power")]
    assert_mock_power(&proxy).await;

    let attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .expect("begin authentication should succeed");
    let state: (String, String) = proxy
        .call("GetState", &())
        .await
        .expect("state query should succeed");
    assert_eq!(state.0, "WaitingForInput");
    #[cfg(feature = "mock-power")]
    assert_mock_power(&proxy).await;

    proxy
        .call::<_, _, ()>("Respond", &(attempt_id.clone(), "password"))
        .await
        .expect("password response should succeed");
    let state: (String, String) = proxy
        .call("GetState", &())
        .await
        .expect("state query should succeed");
    assert_eq!(state.0, "Authenticated");
    #[cfg(feature = "mock-power")]
    assert_mock_power(&proxy).await;

    server.finish().await;
    let logs = backend.get_logs();
    assert!(logs.contains(&attempt_id));
    assert!(logs.contains(r#"operation="Respond""#));
    assert!(logs.contains("authentication succeeded"));
    assert!(!logs.contains("password"));
    assert!(!logs.contains("Password: "));
}

#[tokio::test]
async fn other_callers_cannot_control_or_replace_an_attempt() {
    let _guard = lock().lock().await;
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = spawn_server(fake_auth(listener));
    let _backend = start_backend(&socket);
    let owner_connection = connect_backend().await;
    let owner = make_proxy(&owner_connection).await;
    let other_connection = zbus::Connection::session().await.unwrap();
    let other = make_proxy(&other_connection).await;
    let attempt: String = owner
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();

    for result in [
        other
            .call::<_, _, ()>("Respond", &(attempt.clone(), "intruder"))
            .await,
        other.call::<_, _, ()>("Cancel", &(attempt.clone(),)).await,
        other
            .call::<_, _, ()>("StartSession", &(attempt.clone(), "wayland:test"))
            .await,
        other
            .call::<_, _, String>("BeginAuthentication", &("bob",))
            .await
            .map(|_| ()),
    ] {
        assert!(
            matches!(result, Err(zbus::Error::MethodError(ref name, _, _))
            if name.as_str() == "org.freedesktop.DBus.Error.AccessDenied")
        );
    }
    let state: (String, String) = owner.call("GetState", &()).await.unwrap();
    assert_eq!(state.0, "WaitingForInput");
    owner
        .call::<_, _, ()>("Respond", &(attempt.clone(), "password"))
        .await
        .unwrap();
    let result = other
        .call::<_, _, ()>("StartSession", &(attempt, "wayland:test"))
        .await;
    assert!(
        matches!(result, Err(zbus::Error::MethodError(ref name, _, _))
        if name.as_str() == "org.freedesktop.DBus.Error.AccessDenied")
    );
    let state: (String, String) = owner.call("GetState", &()).await.unwrap();
    assert_eq!(state.0, "Authenticated");
    server.finish().await;
}

#[tokio::test]
async fn same_caller_can_replace_an_attempt() {
    let _guard = lock().lock().await;
    let directory = temp_dir("replacement");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = spawn_server(fake_replacement(listener));
    let _backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;
    let first: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    let second: String = proxy.call("BeginAuthentication", &("bob",)).await.unwrap();
    assert_ne!(first, second);
    assert!(
        proxy
            .call::<_, _, ()>("Respond", &(first, "password"))
            .await
            .is_err()
    );
    proxy.call::<_, _, ()>("Cancel", &(second,)).await.unwrap();
    server.finish().await;
    wait_for_state(&proxy, "Idle").await;
}

#[tokio::test]
async fn owner_disconnect_releases_attempt_for_another_client() {
    let _guard = lock().lock().await;
    let directory = temp_dir("owner-disconnect");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = spawn_server(fake_replacement(listener));
    let _backend = start_backend(&socket);
    let owner = connect_backend().await;
    let _: String = make_proxy(&owner)
        .await
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    owner.close().await.unwrap();
    let other = zbus::Connection::session().await.unwrap();
    let proxy = make_proxy(&other).await;
    wait_for_state(&proxy, "Idle").await;
    let attempt: String = proxy.call("BeginAuthentication", &("bob",)).await.unwrap();
    proxy.call::<_, _, ()>("Cancel", &(attempt,)).await.unwrap();
    server.finish().await;
}

#[tokio::test]
async fn owner_disconnect_interrupts_pending_greetd_io() {
    let _guard = lock().lock().await;
    let directory = temp_dir("disconnect-io");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let (received, request_received) = tokio::sync::oneshot::channel();
    let server = spawn_server(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        assert_eq!(read_request(&mut stream).await["type"], "create_session");
        received.send(()).unwrap();
        let mut byte = [0];
        assert_eq!(
            stream.read(&mut byte).await.unwrap(),
            0,
            "cancel must close interrupted protocol exchange"
        );
    });
    let _backend = start_backend(&socket);
    let owner = connect_backend().await;
    let begin_connection = owner.clone();
    let begin = tokio::spawn(async move {
        make_proxy(&begin_connection)
            .await
            .call::<_, _, String>("BeginAuthentication", &("alice",))
            .await
    });
    tokio::time::timeout(Duration::from_secs(2), request_received)
        .await
        .unwrap()
        .unwrap();
    owner.close().await.unwrap();
    server.finish().await;
    assert!(begin.await.unwrap().is_err());
    let observer = zbus::Connection::session().await.unwrap();
    wait_for_state(&make_proxy(&observer).await, "Idle").await;
}

#[tokio::test]
async fn cancel_interrupts_io_with_a_full_command_queue() {
    let _guard = lock().lock().await;
    let directory = temp_dir("queued-cancel");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let (received, request_received) = tokio::sync::oneshot::channel();
    let server = spawn_server(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        assert_eq!(read_request(&mut stream).await["type"], "create_session");
        send_secret_prompt(&mut stream).await;
        assert_eq!(
            read_request(&mut stream).await["type"],
            "post_auth_message_response"
        );
        received.send(()).unwrap();
        let mut byte = [0];
        assert_eq!(stream.read(&mut byte).await.unwrap(), 0);
    });
    let _backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;
    let attempt: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    let mut responses = tokio::task::JoinSet::new();
    for _ in 0..64 {
        let connection = connection.clone();
        let attempt = attempt.clone();
        responses.spawn(async move {
            make_proxy(&connection)
                .await
                .call::<_, _, ()>("Respond", &(attempt, "queued-secret"))
                .await
        });
    }
    tokio::time::timeout(Duration::from_secs(2), request_received)
        .await
        .unwrap()
        .unwrap();
    #[cfg(feature = "mock-power")]
    tokio::time::timeout(Duration::from_secs(2), assert_mock_power(&proxy))
        .await
        .expect("power requests must not wait for pending greetd I/O");
    // The actor is blocked in greetd and the burst exceeds its 16-command buffer.
    sleep(Duration::from_millis(100)).await;
    tokio::time::timeout(
        Duration::from_secs(2),
        proxy.call::<_, _, ()>("Cancel", &(attempt,)),
    )
    .await
    .expect("Cancel must interrupt I/O before waiting for command capacity")
    .unwrap();
    tokio::time::timeout(Duration::from_secs(2), async {
        while let Some(result) = responses.join_next().await {
            assert!(result.unwrap().is_err());
        }
    })
    .await
    .unwrap();
    server.finish().await;
    wait_for_state(&proxy, "Idle").await;
}

#[tokio::test]
async fn greeter_bus_disconnect_cleans_authentication_and_exits() {
    let directory = temp_dir("bus-disconnect");
    let socket = directory.join("greetd.sock");
    let mut bus = start_private_bus(&directory.join("bus.sock"));
    let listener = UnixListener::bind(&socket).unwrap();
    let server = spawn_server(fake_cancel(listener));
    let mut command = create_backend_command(&socket);
    command.env("DBUS_SESSION_BUS_ADDRESS", &bus.address);
    let mut backend = start_backend_command(&socket, command);
    let connection = zbus::connection::Builder::address(bus.address.as_str())
        .unwrap()
        .build()
        .await
        .unwrap();
    wait_for_backend(&connection).await;
    let _: String = make_proxy(&connection)
        .await
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    bus.stop();
    server.finish().await;
    assert!(!backend.wait_for_exit().await.success());
    assert!(
        backend
            .get_logs()
            .contains("greeter D-Bus connection closed")
    );
}

#[zbus::interface(name = "org.freedesktop.Accounts")]
impl TestAccountsService {
    fn list_cached_users(&self) -> Vec<zbus::zvariant::OwnedObjectPath> {
        Vec::new()
    }
}

struct TestAccountsService;

async fn start_accounts_service(address: &str) -> zbus::Connection {
    zbus::connection::Builder::address(address)
        .unwrap()
        .name("org.freedesktop.Accounts")
        .unwrap()
        .serve_at("/org/freedesktop/Accounts", TestAccountsService)
        .unwrap()
        .build()
        .await
        .unwrap()
}

#[tokio::test]
async fn user_catalog_recovers_after_system_bus_restart() {
    let _guard = lock().lock().await;
    let directory = temp_dir("accounts-recovery");
    let socket = directory.join("greetd.sock");
    let bus_path = directory.join("system-bus.sock");
    let mut system_bus = start_private_bus(&bus_path);
    let accounts = start_accounts_service(&system_bus.address).await;
    let mut command = create_backend_command(&socket);
    command.env("DBUS_SYSTEM_BUS_ADDRESS", &system_bus.address);
    let _backend = start_backend_command(&socket, command);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;
    let users: Vec<(String, String, String)> = proxy.call("ListUsers", &()).await.unwrap();
    assert!(users.is_empty());
    system_bus.stop();
    tokio::time::timeout(Duration::from_secs(2), accounts.closed())
        .await
        .unwrap();
    let unavailable = tokio::time::timeout(
        Duration::from_secs(2),
        proxy.call::<_, _, Vec<(String, String, String)>>("ListUsers", &()),
    )
    .await
    .unwrap();
    assert!(unavailable.is_err());
    system_bus = start_private_bus(&bus_path);
    let _accounts = start_accounts_service(&system_bus.address).await;
    let users: Vec<(String, String, String)> = proxy
        .call("ListUsers", &())
        .await
        .expect("next query should connect to the restarted system bus");
    assert!(users.is_empty());
}

#[tokio::test]
async fn startup_failure_is_logged_with_its_cause() {
    let directory = temp_dir("startup-failure");
    let socket = directory.join("greetd.sock");
    let mut command = create_backend_command(&socket);
    command.env(
        "DBUS_SESSION_BUS_ADDRESS",
        format!("unix:path={}", directory.join("missing-bus").display()),
    );
    let mut backend = start_backend_command(&socket, command);
    assert!(!backend.wait_for_exit().await.success());
    let logs = backend.get_logs();
    assert!(logs.contains("startup_failed"));
    assert!(logs.contains("No such file or directory"));
}

#[tokio::test]
async fn greetd_connection_failure_retains_source_in_logs() {
    let _guard = lock().lock().await;
    let directory = temp_dir("connect-failure");
    let socket = directory.join("missing-greetd.sock");
    let backend = start_backend(&socket);
    let connection = connect_backend().await;
    let result = make_proxy(&connection)
        .await
        .call::<_, _, String>("BeginAuthentication", &("alice",))
        .await;
    assert!(result.is_err());
    let logs = backend.get_logs();
    assert!(logs.contains("authentication transaction failed"));
    assert!(logs.contains("attempt-0000000000000001"));
    assert!(logs.contains("No such file or directory"));
}

#[tokio::test]
async fn blank_username_is_rejected() {
    let _guard = lock().lock().await;
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let _backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;

    let result: zbus::Result<String> = proxy.call("BeginAuthentication", &("   ",)).await;

    assert!(result.is_err());
}

#[tokio::test]
async fn auth_error_without_user_input_does_not_retry() {
    let _guard = lock().lock().await;
    let directory = temp_dir("no-input-retry");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = spawn_server(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        assert_eq!(read_request(&mut stream).await["type"], "create_session");
        write_response(
            &mut stream,
            serde_json::json!({
                "type": "auth_message",
                "auth_message_type": "error",
                "auth_message": "Authentication provider unavailable"
            }),
        )
        .await;
        let acknowledgment = read_request(&mut stream).await;
        assert_eq!(acknowledgment["type"], "post_auth_message_response");
        assert!(acknowledgment.get("response").is_none());
        write_response(
            &mut stream,
            serde_json::json!({
                "type": "error",
                "error_type": "auth_error",
                "description": "authentication failed before user input"
            }),
        )
        .await;
        assert_eq!(read_request(&mut stream).await["type"], "cancel_session");
        write_response(&mut stream, serde_json::json!({"type": "success"})).await;
        assert!(
            tokio::time::timeout(Duration::from_millis(300), listener.accept())
                .await
                .is_err(),
            "an automatic PAM acknowledgment must not trigger another login attempt"
        );
    });
    let _backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;
    let result = tokio::time::timeout(
        Duration::from_secs(2),
        proxy.call::<_, _, String>("BeginAuthentication", &("alice",)),
    )
    .await
    .unwrap();
    assert!(result.is_err());
    let state: (String, String) = proxy.call("GetState", &()).await.unwrap();
    assert_eq!(state.0, "Failed");
    server.finish().await;
}

#[tokio::test]
async fn wrong_password_prompts_again() {
    let _guard = lock().lock().await;
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_bad_password_then_prompt(listener));
    let _backend = start_backend(&socket);
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

    proxy
        .call::<_, _, ()>("Respond", &(attempt_id.clone(), "wrong"))
        .await
        .expect("rejected credential should restart the prompt");

    let state: (String, String) = proxy
        .call("GetState", &())
        .await
        .expect("state query should succeed");
    assert_eq!(state.0, "WaitingForInput");

    server.finish().await;
}

#[tokio::test]
async fn stale_attempt() {
    let _guard = lock().lock().await;
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_auth(listener));
    let _backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;

    let _attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    let result: zbus::Result<()> = proxy.call("Respond", &("attempt-stale", "password")).await;

    assert!(result.is_err());
    server.task.abort();
}

#[tokio::test]
async fn respond_early() {
    let _guard = lock().lock().await;
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_delayed_prompt(listener));
    let _backend = start_backend(&socket);
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
    server.finish().await;
}

#[tokio::test]
async fn bad_session() {
    let _guard = lock().lock().await;
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_auth(listener));
    let _backend = start_backend(&socket);
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

    server.finish().await;
}

#[tokio::test]
async fn cancel_to_idle() {
    let _guard = lock().lock().await;
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_cancel(listener));
    let _backend = start_backend(&socket);
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
    server.finish().await;
}

#[tokio::test]
async fn sigterm_cancels_authentication_and_exits() {
    let _guard = lock().lock().await;
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = spawn_server(fake_cancel(listener));
    let mut backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;
    let _: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    assert!(
        Command::new("kill")
            .args(["-TERM", &backend.child.id().to_string()])
            .status()
            .unwrap()
            .success()
    );
    server.finish().await;
    assert!(backend.wait_for_exit().await.success());
}

#[tokio::test]
async fn bad_power_action() {
    let _guard = lock().lock().await;
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let _backend = start_backend(&socket);
    let connection = connect_backend().await;
    let proxy = make_proxy(&connection).await;

    let result: zbus::Result<()> = proxy.call("PowerAction", &("Shutdown",)).await;

    assert!(result.is_err());
}

#[tokio::test]
async fn start_session() {
    let _guard = lock().lock().await;
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let session_root = temp_dir("sessions");
    write_session(&session_root, "test.desktop", "Test");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_start(listener, false));
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

    assert!(backend.wait_for_exit().await.success());
    server.finish().await;
}

#[tokio::test]
async fn start_session_fails() {
    let _guard = lock().lock().await;
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let session_root = temp_dir("sessions-fail");
    write_session(&session_root, "test.desktop", "Test");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_start(listener, true));
    let _backend = start_backend_for_sessions(&socket, &session_root);
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
    server.finish().await;
}

async fn fake_replacement(listener: UnixListener) {
    for username in ["alice", "bob"] {
        let (mut stream, _) = listener.accept().await.unwrap();
        let create = read_request(&mut stream).await;
        assert_eq!(create["type"], "create_session");
        assert_eq!(create["username"], username);
        send_secret_prompt(&mut stream).await;
        assert_eq!(read_request(&mut stream).await["type"], "cancel_session");
        write_response(&mut stream, serde_json::json!({"type": "success"})).await;
    }
}

async fn send_secret_prompt(stream: &mut UnixStream) {
    write_response(
        stream,
        serde_json::json!({
            "type": "auth_message", "auth_message_type": "secret", "auth_message": "Password: "
        }),
    )
    .await;
}

async fn wait_for_state(proxy: &zbus::Proxy<'_>, expected: &str) {
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let (state, _): (String, String) = proxy.call("GetState", &()).await.unwrap();
            if state == expected {
                break;
            }
            sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("backend should reach expected state");
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

async fn fake_bad_password_then_prompt(listener: UnixListener) {
    {
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
        // Keep greetd's configured session until the explicit cancel request.
        // Reconnecting alone must not stand in for server-side cleanup.
        assert_eq!(read_request(&mut stream).await["type"], "cancel_session");
        write_response(&mut stream, serde_json::json!({"type": "success"})).await;
    }

    let (mut stream, _) = listener
        .accept()
        .await
        .expect("backend should reconnect after a rejected credential");
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
    let connection = zbus::Connection::session().await.unwrap();
    wait_for_backend(&connection).await;
    connection
}

async fn wait_for_backend(connection: &zbus::Connection) {
    let proxy = make_proxy(connection).await;
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            if proxy
                .call::<_, _, (String, String)>("GetState", &())
                .await
                .is_ok()
            {
                break;
            }
            sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("backend did not appear on D-Bus");
}

async fn make_proxy(connection: &zbus::Connection) -> zbus::Proxy<'_> {
    Proxy::new(
        connection,
        "io.akari.Greeter",
        "/io/akari/Greeter",
        "io.akari.Greeter1",
    )
    .await
    .expect("backend proxy should be available")
}

fn lock() -> &'static tokio::sync::Mutex<()> {
    TEST_LOCK.get_or_init(|| tokio::sync::Mutex::new(()))
}

struct BusProcess {
    child: Child,
    address: String,
}

impl BusProcess {
    fn stop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

impl Drop for BusProcess {
    fn drop(&mut self) {
        self.stop();
    }
}

fn start_private_bus(path: &Path) -> BusProcess {
    let address = format!("unix:path={}", path.display());
    let child = Command::new("dbus-daemon")
        .args([
            "--session",
            "--nofork",
            "--print-address=1",
            "--address",
            &address,
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .unwrap();
    let mut bus = BusProcess { child, address };
    let mut ready = String::new();
    BufReader::new(bus.child.stdout.take().unwrap())
        .read_line(&mut ready)
        .unwrap();
    assert!(!ready.is_empty(), "private bus must publish its address");
    bus
}

struct BackendProcess {
    child: Child,
    log_path: PathBuf,
}

impl BackendProcess {
    async fn wait_for_exit(&mut self) -> ExitStatus {
        tokio::time::timeout(Duration::from_secs(3), async {
            loop {
                if let Some(status) = self.child.try_wait().unwrap() {
                    return status;
                }
                sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .expect("backend should exit without being killed")
    }

    fn get_logs(&self) -> String {
        std::fs::read_to_string(&self.log_path).unwrap()
    }
}

impl Drop for BackendProcess {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        if std::thread::panicking() {
            eprintln!(
                "backend output from {}:\n{}",
                self.log_path.display(),
                std::fs::read_to_string(&self.log_path).unwrap_or_default()
            );
        }
        let _ = std::fs::remove_file(&self.log_path);
    }
}

fn create_backend_command(socket: &Path) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_backend"));
    command
        .env("GREETD_SOCK", socket)
        .env("RUST_LOG", "backend=info,warn");
    command
}

fn start_backend(socket: &Path) -> BackendProcess {
    start_backend_command(socket, create_backend_command(socket))
}

fn start_backend_for_sessions(socket: &Path, session_root: &Path) -> BackendProcess {
    let mut command = create_backend_command(socket);
    command
        .env("AKARI_WAYLAND_SESSIONS", session_root)
        .env("AKARI_X11_SESSIONS", "/akari/missing-x11");
    start_backend_command(socket, command)
}

fn start_backend_command(socket: &Path, mut command: Command) -> BackendProcess {
    let log_path = socket.with_extension("log");
    let output = std::fs::File::create(&log_path).unwrap();
    let child = command
        .stdin(Stdio::null())
        .stdout(output.try_clone().unwrap())
        .stderr(output)
        .spawn()
        .expect("backend process should start");
    BackendProcess { child, log_path }
}

struct ServerTask {
    task: tokio::task::JoinHandle<()>,
}

impl ServerTask {
    async fn finish(mut self) {
        tokio::time::timeout(Duration::from_secs(3), &mut self.task)
            .await
            .expect("fake greetd should finish")
            .expect("fake greetd should not panic");
    }
}

impl Drop for ServerTask {
    fn drop(&mut self) {
        self.task.abort();
    }
}

fn spawn_server(future: impl std::future::Future<Output = ()> + Send + 'static) -> ServerTask {
    ServerTask {
        task: tokio::spawn(future),
    }
}

/// Owns the whole temporary tree so sockets and desktop files survive until
/// dependent guards stop, and are removed during unwinding as well.
struct TestDirectory(PathBuf);

impl std::ops::Deref for TestDirectory {
    type Target = Path;
    fn deref(&self) -> &Path {
        &self.0
    }
}

impl Drop for TestDirectory {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn temp_dir(label: &str) -> TestDirectory {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!("akari-{label}-{}-{nonce}", std::process::id()));
    std::fs::create_dir(&path).unwrap();
    TestDirectory(path)
}

fn write_session(root: &Path, name: &str, display_name: &str) {
    std::fs::write(root.join(name), format!(
        "[Desktop Entry]\nType=Application\nName={display_name}\nExec=/usr/bin/true\nDesktopNames=test\n"
    )).unwrap();
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

#[cfg(feature = "mock-power")]
async fn assert_mock_power(proxy: &Proxy<'_>) {
    let before: (String, String) = proxy.call("GetState", &()).await.unwrap();
    for action in ["PowerOff", "Reboot", "Suspend", "Hibernate"] {
        proxy
            .call::<_, _, ()>("PowerAction", &(action,))
            .await
            .unwrap();
    }
    let after: (String, String) = proxy.call("GetState", &()).await.unwrap();
    assert_eq!(after, before);
}
