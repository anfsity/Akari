#![cfg(not(feature = "mock"))]

use std::{
    io::{BufRead, BufReader},
    os::unix::ffi::OsStrExt,
    path::{Path, PathBuf},
    process::{Child, Command, ExitStatus, Stdio},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use futures_util::StreamExt;
use serde_json::Value;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{UnixListener, UnixStream},
    time::sleep,
};
use zbus::Proxy;

#[tokio::test]
async fn auth_roundtrip() {
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_auth(listener));
    let backend = start_backend(&socket);

    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;

    #[cfg(feature = "mock-power")]
    assert_mock_power(&proxy).await;

    let attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .expect("begin authentication should succeed");
    wait_for_state(&proxy, "WaitingForInput").await;
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
    wait_for_state(&proxy, "Authenticated").await;
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
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = spawn_server(fake_auth(listener));
    let backend = start_backend(&socket);
    let owner_connection = backend.connect().await;
    let owner = create_proxy(&owner_connection).await;
    let other_connection = backend.connect_client().await;
    let other = create_proxy(&other_connection).await;
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
    wait_for_state(&owner, "Authenticated").await;
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
    let directory = temp_dir("replacement");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = spawn_server(fake_replacement(listener));
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;
    let first: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    wait_for_state(&proxy, "WaitingForInput").await;
    let second: String = proxy.call("BeginAuthentication", &("bob",)).await.unwrap();
    wait_for_state(&proxy, "WaitingForInput").await;
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
    let directory = temp_dir("owner-disconnect");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = spawn_server(fake_replacement(listener));
    let backend = start_backend(&socket);
    let owner = backend.connect().await;
    let _: String = create_proxy(&owner)
        .await
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    wait_for_state(&create_proxy(&owner).await, "WaitingForInput").await;
    owner.close().await.unwrap();
    let other = backend.connect_client().await;
    let proxy = create_proxy(&other).await;
    wait_for_state(&proxy, "Idle").await;
    let attempt: String = proxy.call("BeginAuthentication", &("bob",)).await.unwrap();
    wait_for_state(&proxy, "WaitingForInput").await;
    proxy.call::<_, _, ()>("Cancel", &(attempt,)).await.unwrap();
    server.finish().await;
}

#[tokio::test]
async fn owner_disconnect_interrupts_pending_greetd_io() {
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
    let backend = start_backend(&socket);
    let owner = backend.connect().await;
    let begin_connection = owner.clone();
    let begin = tokio::spawn(async move {
        create_proxy(&begin_connection)
            .await
            .call::<_, _, String>("BeginAuthentication", &("alice",))
            .await
    });
    tokio::time::timeout(Duration::from_secs(2), request_received)
        .await
        .unwrap()
        .unwrap();
    assert!(begin.await.unwrap().is_ok());
    owner.close().await.unwrap();
    server.finish().await;
    let observer = backend.connect_client().await;
    wait_for_state(&create_proxy(&observer).await, "Idle").await;
}

#[tokio::test]
async fn cancel_interrupts_io_with_a_full_command_queue() {
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
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;
    let attempt: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    let mut responses = tokio::task::JoinSet::new();
    for _ in 0..64 {
        let connection = connection.clone();
        let attempt = attempt.clone();
        responses.spawn(async move {
            create_proxy(&connection)
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
    let mut accepted = 0_usize;
    let mut rejected = 0_usize;
    tokio::time::timeout(Duration::from_secs(2), async {
        while let Some(result) = responses.join_next().await {
            match result.unwrap() {
                Ok(()) => accepted += 1,
                Err(_) => rejected += 1,
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(accepted, 1);
    assert_eq!(rejected, 63);
    wait_for_state(&proxy, "Idle").await;
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
    let mut backend = start_backend_process(&socket, command);
    let connection = bus.connect().await;
    wait_for_backend(&connection).await;
    let _: String = create_proxy(&connection)
        .await
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    wait_for_state(&create_proxy(&connection).await, "WaitingForInput").await;
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
    let directory = temp_dir("accounts-recovery");
    let socket = directory.join("greetd.sock");
    let bus_path = directory.join("system-bus.sock");
    let mut system_bus = start_private_bus(&bus_path);
    let accounts = start_accounts_service(&system_bus.address).await;
    let mut command = create_backend_command(&socket);
    command.env("DBUS_SYSTEM_BUS_ADDRESS", &system_bus.address);
    let backend = start_backend_command(&socket, command);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;
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
    let mut backend = start_backend_process(&socket, command);
    assert!(!backend.wait_for_exit().await.success());
    let logs = backend.get_logs();
    assert!(logs.contains("startup_failed"));
    assert!(logs.contains("No such file or directory"));
}

#[tokio::test]
async fn greetd_connection_failure_retains_source_in_logs() {
    let directory = temp_dir("connect-failure");
    let socket = directory.join("missing-greetd.sock");
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;
    let result = proxy
        .call::<_, _, String>("BeginAuthentication", &("alice",))
        .await;
    assert!(result.is_ok());
    wait_for_state(&proxy, "Failed").await;
    let logs = backend.get_logs();
    assert!(logs.contains("authentication transaction failed"));
    assert!(logs.contains("attempt-0000000000000001"));
    assert!(logs.contains("No such file or directory"));
}

#[tokio::test]
async fn blank_username_is_rejected() {
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;

    let result: zbus::Result<String> = proxy.call("BeginAuthentication", &("   ",)).await;

    assert!(result.is_err());
}

#[tokio::test]
async fn auth_error_without_user_input_does_not_retry() {
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
        write_response(
            &mut stream,
            serde_json::json!({"type": "error", "error_type": "error",
                "description": "unable to send message: Connection refused (os error 111)"}),
        )
        .await;
        assert!(
            tokio::time::timeout(Duration::from_millis(300), listener.accept())
                .await
                .is_err(),
            "an automatic PAM acknowledgment must not trigger another login attempt"
        );
    });
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;
    let result = tokio::time::timeout(
        Duration::from_secs(2),
        proxy.call::<_, _, String>("BeginAuthentication", &("alice",)),
    )
    .await
    .unwrap();
    assert!(result.is_ok());
    wait_for_state(&proxy, "Failed").await;
    let state: (String, String) = proxy.call("GetState", &()).await.unwrap();
    assert_eq!(state.0, "Failed");
    server.finish().await;
}

#[tokio::test]
async fn begin_authentication_recovers_after_failed_state() {
    let directory = temp_dir("retry-after-failed");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = spawn_server(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        assert_eq!(read_request(&mut stream).await["type"], "create_session");
        write_response(
            &mut stream,
            serde_json::json!({
                "type": "error",
                "error_type": "auth_error",
                "description": "authentication failed"
            }),
        )
        .await;
        assert_eq!(read_request(&mut stream).await["type"], "cancel_session");
        write_response(&mut stream, serde_json::json!({"type": "success"})).await;

        let (mut stream, _) = listener.accept().await.unwrap();
        let create = read_request(&mut stream).await;
        assert_eq!(create["type"], "create_session");
        assert_eq!(create["username"], "bob");
        send_secret_prompt(&mut stream).await;
        let response = read_request(&mut stream).await;
        assert_eq!(response["response"], "password");
        write_response(&mut stream, serde_json::json!({"type": "success"})).await;
    });
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;

    let first: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    wait_for_state(&proxy, "Failed").await;

    let second: String = proxy.call("BeginAuthentication", &("bob",)).await.unwrap();
    assert_ne!(first, second);
    wait_for_state(&proxy, "WaitingForInput").await;
    proxy
        .call::<_, _, ()>("Respond", &(second, "password"))
        .await
        .unwrap();
    wait_for_state(&proxy, "Authenticated").await;
    let state: (String, String) = proxy.call("GetState", &()).await.unwrap();
    assert_eq!(state.0, "Authenticated");
    server.finish().await;
}

#[tokio::test]
async fn wrong_password_prompts_again() {
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_bad_password_then_prompt(listener));
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;

    let attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .expect("begin authentication should succeed");
    wait_for_state(&proxy, "WaitingForInput").await;
    let mut prompts = proxy.receive_signal("Prompt").await.unwrap();
    let state: (String, String) = proxy
        .call("GetState", &())
        .await
        .expect("state query should succeed");
    assert_eq!(state.0, "WaitingForInput");

    for _ in 0..2 {
        proxy
            .call::<_, _, ()>("Respond", &(attempt_id.clone(), "wrong"))
            .await
            .expect("rejected credential should be accepted for retry");
        for expected_kind in ["error", "secret"] {
            let prompt = tokio::time::timeout(Duration::from_secs(2), prompts.next())
                .await
                .unwrap()
                .unwrap();
            let (_, kind, _): (String, String, String) = prompt.body().deserialize().unwrap();
            assert_eq!(kind, expected_kind);
        }
        wait_for_state(&proxy, "WaitingForInput").await;
    }
    proxy
        .call::<_, _, ()>("Respond", &(attempt_id, "password"))
        .await
        .unwrap();
    wait_for_state(&proxy, "Authenticated").await;
    let state: (String, String) = proxy.call("GetState", &()).await.unwrap();
    assert_eq!(state.0, "Authenticated");

    server.finish().await;
}

#[tokio::test]
async fn invalid_rejection_cleanup_does_not_retry() {
    for unexpected_prompt in [false, true] {
        let directory = temp_dir("rejection-cleanup");
        let socket = directory.join("greetd.sock");
        let listener = UnixListener::bind(&socket).unwrap();
        let server = spawn_server(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            assert_eq!(read_request(&mut stream).await["type"], "create_session");
            send_secret_prompt(&mut stream).await;
            assert_eq!(read_request(&mut stream).await["response"], "wrong");
            write_response(
                &mut stream,
                serde_json::json!({"type": "error", "error_type": "auth_error",
                    "description": "authentication failed"}),
            )
            .await;
            assert_eq!(read_request(&mut stream).await["type"], "cancel_session");
            if unexpected_prompt {
                send_secret_prompt(&mut stream).await;
            }
            drop(stream);
            assert!(
                tokio::time::timeout(Duration::from_millis(300), listener.accept())
                    .await
                    .is_err()
            );
        });
        let backend = start_backend(&socket);
        let connection = backend.connect().await;
        let proxy = create_proxy(&connection).await;
        let attempt: String = proxy
            .call("BeginAuthentication", &("alice",))
            .await
            .unwrap();
        wait_for_state(&proxy, "WaitingForInput").await;
        proxy
            .call::<_, _, ()>("Respond", &(attempt, "wrong"))
            .await
            .unwrap();
        wait_for_state(&proxy, "Failed").await;
        server.finish().await;
    }
}

#[tokio::test]
async fn stale_attempt() {
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_auth(listener));
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;

    let _attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    let result: zbus::Result<()> = proxy.call("Respond", &("attempt-stale", "password")).await;

    assert!(result.is_err());
    server.task.abort();
}

#[tokio::test]
async fn respond_without_prompt_is_rejected() {
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(async move {
        let (mut stream, _) = listener.accept().await.expect("backend should connect");
        let create = read_request(&mut stream).await;
        assert_eq!(create["type"], "create_session");
        write_response(&mut stream, serde_json::json!({ "type": "success" })).await;
    });
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;

    let attempt: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .expect("begin authentication should succeed");
    wait_for_state(&proxy, "Authenticated").await;
    let result: zbus::Result<()> = proxy.call("Respond", &(attempt, "password")).await;

    let error = result.expect_err("Respond must fail when no prompt is waiting");
    assert!(
        error
            .to_string()
            .contains("operation is not valid in state Authenticated")
    );
    server.finish().await;
}

#[tokio::test]
async fn facial_authentication_progress_and_password_fallback() {
    for password_fallback in [false, true] {
        let directory = temp_dir("face-auth");
        let socket = directory.join("greetd.sock");
        let sessions = temp_dir("face-sessions");
        write_session(&sessions, "test.desktop", "Test");
        let listener = UnixListener::bind(&socket).unwrap();
        let (finish_scan, scan_finished) = tokio::sync::oneshot::channel();
        let server = spawn_server(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let request = read_request(&mut stream).await;
            assert_eq!(request["type"], "create_session");
            assert_eq!(request["username"], "alice");
            write_response(
                &mut stream,
                serde_json::json!({
                    "type": "auth_message",
                    "auth_message_type": "info",
                    "auth_message": "Attempting facial authentication"
                }),
            )
            .await;
            let acknowledgment = read_request(&mut stream).await;
            assert_eq!(acknowledgment["type"], "post_auth_message_response");
            assert!(acknowledgment.get("response").is_none());
            scan_finished.await.unwrap();
            if password_fallback {
                write_response(
                    &mut stream,
                    serde_json::json!({
                        "type": "auth_message", "auth_message_type": "error",
                        "auth_message": "Face detection timeout reached"
                    }),
                )
                .await;
                let acknowledgment = read_request(&mut stream).await;
                assert!(acknowledgment.get("response").is_none());
                send_secret_prompt(&mut stream).await;
                assert_eq!(read_request(&mut stream).await["response"], "password");
            }
            write_response(&mut stream, serde_json::json!({"type": "success"})).await;
            assert_eq!(read_request(&mut stream).await["type"], "start_session");
            write_response(&mut stream, serde_json::json!({"type": "success"})).await;
        });
        let mut backend = start_backend_for_sessions(&socket, &sessions);
        let connection = backend.connect().await;
        let proxy = create_proxy(&connection).await;
        let mut prompts = proxy.receive_signal("Prompt").await.unwrap();
        let attempt: String = tokio::time::timeout(
            Duration::from_secs(2),
            proxy.call("BeginAuthentication", &("alice",)),
        )
        .await
        .expect("attempt ID must be returned before the scan finishes")
        .unwrap();
        let prompt = tokio::time::timeout(Duration::from_secs(2), prompts.next())
            .await
            .unwrap()
            .unwrap();
        let (prompt_attempt, kind, text): (String, String, String) =
            prompt.body().deserialize().unwrap();
        assert_eq!(prompt_attempt, attempt);
        assert_eq!(kind, "info");
        assert_eq!(text, "Attempting facial authentication");
        wait_for_state(&proxy, "SubmittingResponse").await;
        finish_scan.send(()).unwrap();
        if password_fallback {
            wait_for_state(&proxy, "WaitingForInput").await;
            proxy
                .call::<_, _, ()>("Respond", &(attempt.clone(), "password"))
                .await
                .unwrap();
        }
        wait_for_state(&proxy, "Authenticated").await;
        proxy
            .call::<_, _, ()>("StartSession", &(attempt, "wayland:test"))
            .await
            .unwrap();
        server.finish().await;
        assert!(backend.wait_for_exit().await.success());
    }
}

#[tokio::test]
async fn bad_session() {
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_auth(listener));
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;

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
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_cancel(listener));
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;

    let attempt_id: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    wait_for_state(&proxy, "WaitingForInput").await;
    let result: zbus::Result<()> = proxy.call("Cancel", &(attempt_id,)).await;
    assert!(result.is_ok());

    let state: (String, String) = proxy.call("GetState", &()).await.unwrap();
    assert_eq!(state.0, "Idle");
    server.finish().await;
}

#[tokio::test]
async fn sigterm_cancels_authentication_and_exits() {
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = spawn_server(fake_cancel(listener));
    let mut backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;
    let _: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    wait_for_state(&proxy, "WaitingForInput").await;
    assert!(
        Command::new("kill")
            .args(["-TERM", &backend.id().to_string()])
            .status()
            .unwrap()
            .success()
    );
    server.finish().await;
    assert!(backend.wait_for_exit().await.success());
}

#[tokio::test]
async fn bad_power_action() {
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;

    let result: zbus::Result<()> = proxy.call("PowerAction", &("Shutdown",)).await;

    assert!(result.is_err());
}

#[tokio::test]
async fn start_session() {
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let session_root = temp_dir("sessions");
    write_session(&session_root, "test.desktop", "Test");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_start(listener, false));
    let mut backend = start_backend_for_sessions(&socket, &session_root);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;

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
    let directory = temp_dir("dbus");
    let socket = directory.join("greetd.sock");
    let session_root = temp_dir("sessions-fail");
    write_session(&session_root, "test.desktop", "Test");
    let listener = UnixListener::bind(&socket).expect("fake greetd socket should bind");
    let server = spawn_server(fake_start(listener, true));
    let backend = start_backend_for_sessions(&socket, &session_root);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;

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
    send_secret_prompt(&mut stream).await;

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
    for cancel_fails in [true, false] {
        let (mut stream, _) = listener.accept().await.expect("backend should connect");
        let create = read_request(&mut stream).await;
        assert_eq!(create["type"], "create_session");
        send_secret_prompt(&mut stream).await;

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
        // greetd clears the configuring slot even when the departed PAM
        // worker makes cancellation return an Error instead of Success.
        assert_eq!(read_request(&mut stream).await["type"], "cancel_session");
        let reply = if cancel_fails {
            serde_json::json!({"type": "error", "error_type": "error",
                "description": "unable to send message: Connection refused (os error 111)"})
        } else {
            serde_json::json!({"type": "success"})
        };
        write_response(&mut stream, reply).await;
        assert_eq!(stream.read(&mut [0]).await.unwrap(), 0);
    }

    let (mut stream, _) = listener
        .accept()
        .await
        .expect("backend should reconnect after a rejected credential");
    let create = read_request(&mut stream).await;
    assert_eq!(create["type"], "create_session");
    send_secret_prompt(&mut stream).await;
    assert_eq!(read_request(&mut stream).await["response"], "password");
    write_response(&mut stream, serde_json::json!({"type": "success"})).await;
}

async fn fake_cancel(listener: UnixListener) {
    let (mut stream, _) = listener.accept().await.expect("backend should connect");
    let create = read_request(&mut stream).await;
    assert_eq!(create["type"], "create_session");
    send_secret_prompt(&mut stream).await;

    let cancel = read_request(&mut stream).await;
    assert_eq!(cancel["type"], "cancel_session");
    write_response(&mut stream, serde_json::json!({ "type": "success" })).await;
}

async fn fake_start(listener: UnixListener, fail_start: bool) {
    let (mut stream, _) = listener.accept().await.expect("backend should connect");
    let _ = read_request(&mut stream).await;
    send_secret_prompt(&mut stream).await;
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
    let environment: Vec<_> = start["env"]
        .as_array()
        .unwrap()
        .iter()
        .map(|value| value.as_str().unwrap().split_once('=').unwrap())
        .collect();
    let invocation: Value = serde_json::from_str(
        environment
            .iter()
            .find(|(name, _)| *name == "AKARI_SESSION_INVOCATION")
            .unwrap()
            .1,
    )
    .unwrap();
    assert_eq!(invocation["command"], serde_json::json!(["/usr/bin/true"]));
    assert_eq!(invocation["session_id"], "wayland:test");
    assert!(environment.contains(&("XDG_SESSION_TYPE", "wayland")));
    assert!(environment.contains(&("XDG_CURRENT_DESKTOP", "test")));
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
        // Execute the actual received wire command with greetd's profile/sh
        // semantics, using a temporary user home and a harmless desktop entry.
        let home = temp_dir("session-handoff");
        let command = start["cmd"]
            .as_array()
            .unwrap()
            .iter()
            .map(|value| value.as_str().unwrap())
            .collect::<Vec<_>>()
            .join(" ");
        let output = Command::new("/bin/sh").args(["-c", &format!(
            "[ -f /etc/profile ] && . /etc/profile; [ -f \"$HOME/.profile\" ] && . \"$HOME/.profile\"; exec {command}"
        )]).env_clear().envs(environment).env("HOME", &*home).env("SHELL", "/bin/sh")
            .output().unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(home.join(".local/state/akari/sessions").is_dir());
    }
}

async fn wait_for_backend(connection: &zbus::Connection) {
    let proxy = create_proxy(connection).await;
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

async fn create_proxy(connection: &zbus::Connection) -> zbus::Proxy<'_> {
    Proxy::new(
        connection,
        "io.akari.Greeter",
        "/io/akari/Greeter",
        "io.akari.Greeter1",
    )
    .await
    .expect("backend proxy should be available")
}

struct BusProcess {
    child: Child,
    address: String,
}

impl BusProcess {
    async fn connect(&self) -> zbus::Connection {
        zbus::connection::Builder::address(self.address.as_str())
            .unwrap()
            .build()
            .await
            .unwrap()
    }

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

fn encode_dbus_unix_path(path: &Path) -> String {
    let mut encoded = String::from("unix:path=");
    for &byte in path.as_os_str().as_bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'.' | b'/' | b'-') {
            encoded.push(char::from(byte));
        } else {
            encoded.push_str(&format!("%{byte:02X}"));
        }
    }
    encoded
}

fn start_private_bus(path: &Path) -> BusProcess {
    let address = encode_dbus_unix_path(path);
    let child = Command::new("dbus-daemon")
        .args([
            "--session",
            "--nofork",
            "--nopidfile",
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

/// Pairs a backend child with its dedicated session D-Bus daemon so every test
/// runs hermetically without requiring or touching an ambient desktop bus.
/// Field order ensures `process` terminates before `session_bus` is stopped.
struct TestBackend {
    process: BackendProcess,
    session_bus: BusProcess,
}

impl TestBackend {
    async fn connect(&self) -> zbus::Connection {
        let connection = self.session_bus.connect().await;
        wait_for_backend(&connection).await;
        connection
    }

    async fn connect_client(&self) -> zbus::Connection {
        self.session_bus.connect().await
    }

    async fn wait_for_exit(&mut self) -> ExitStatus {
        self.process.wait_for_exit().await
    }

    fn get_logs(&self) -> String {
        self.process.get_logs()
    }

    fn id(&self) -> u32 {
        self.process.child.id()
    }
}

fn create_backend_command(socket: &Path) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_backend"));
    command
        .env("GREETD_SOCK", socket)
        .env(
            "DBUS_SYSTEM_BUS_ADDRESS",
            "unix:path=/akari/missing-system-bus",
        )
        .env("RUST_LOG", "backend=info,warn");
    command
}

fn start_backend(socket: &Path) -> TestBackend {
    start_backend_command(socket, create_backend_command(socket))
}

fn start_backend_for_sessions(socket: &Path, session_root: &Path) -> TestBackend {
    let mut command = create_backend_command(socket);
    command
        .env("AKARI_WAYLAND_SESSIONS", session_root)
        .env("AKARI_X11_SESSIONS", "/akari/missing-x11");
    start_backend_command(socket, command)
}

fn start_backend_command(socket: &Path, mut command: Command) -> TestBackend {
    let session_bus = start_private_bus(&socket.with_extension("session-bus"));
    command.env("DBUS_SESSION_BUS_ADDRESS", &session_bus.address);
    let process = start_backend_process(socket, command);
    TestBackend {
        process,
        session_bus,
    }
}

fn start_backend_process(socket: &Path, mut command: Command) -> BackendProcess {
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

#[tokio::test]
async fn failed_previous_cancel_does_not_block_replacement_and_prompts_are_sanitized() {
    let directory = temp_dir("replace-sanitized");
    let socket = directory.join("greetd.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = spawn_server(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        assert_eq!(read_request(&mut stream).await["type"], "create_session");
        send_secret_prompt(&mut stream).await;
        assert_eq!(read_request(&mut stream).await["type"], "cancel_session");
        write_response(
            &mut stream,
            serde_json::json!({
                "type": "error",
                "error_type": "error",
                "description": "stale worker cancel error"
            }),
        )
        .await;

        let (mut stream, _) = listener.accept().await.unwrap();
        assert_eq!(read_request(&mut stream).await["type"], "create_session");
        let dirty = format!("Prompt:\r\u{001b}[31m{}\n{}", "a", "z".repeat(600));
        write_response(
            &mut stream,
            serde_json::json!({
                "type": "auth_message",
                "auth_message_type": "visible",
                "auth_message": dirty,
            }),
        )
        .await;
        assert_eq!(read_request(&mut stream).await["type"], "cancel_session");
        write_response(&mut stream, serde_json::json!({"type": "success"})).await;
    });
    let backend = start_backend(&socket);
    let connection = backend.connect().await;
    let proxy = create_proxy(&connection).await;
    let mut prompts = proxy.receive_signal("Prompt").await.unwrap();

    let first: String = proxy
        .call("BeginAuthentication", &("alice",))
        .await
        .unwrap();
    let _ = prompts.next().await.unwrap();
    wait_for_state(&proxy, "WaitingForInput").await;

    let second: String = proxy.call("BeginAuthentication", &("bob",)).await.unwrap();
    assert_ne!(first, second);
    let prompt = tokio::time::timeout(Duration::from_secs(2), prompts.next())
        .await
        .unwrap()
        .unwrap();
    let (attempt_id, _, text): (String, String, String) = prompt.body().deserialize().unwrap();
    assert_eq!(attempt_id, second);
    assert!(!text.contains('\r'));
    assert!(!text.contains('\u{001b}'));
    assert_eq!(text.chars().count(), 512);

    proxy.call::<_, _, ()>("Cancel", &(second,)).await.unwrap();
    server.finish().await;
}
