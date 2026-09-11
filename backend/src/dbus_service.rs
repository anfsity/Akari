//! D-Bus bridge between the Flutter greeter, greetd, session catalogs, and logind.

use std::sync::atomic::{AtomicBool, Ordering};
use std::vec;
use std::{sync::Arc, time::Duration};

use futures_util::StreamExt;
use tokio::{
    sync::{Mutex, Notify, OwnedMutexGuard},
    time::timeout,
};
use tokio_util::sync::CancellationToken;
use zbus::{fdo, interface, message::Header, object_server::SignalEmitter};

use crate::{
    greetd::{GreetdError, GreetdResponse, GreetdTransport},
    session_catalog::{SessionCatalog, SessionCatalogError, SessionEntry},
    state::{AuthState, AuthStateMachine, BeginAuthenticationError, StateEvent},
    users::{UserCatalog},
};

pub const BUS_NAME: &str = "io.mozais.Greeter";
pub const OBJECT_PATH: &str = "/io/mozais/Greeter";

const CANCEL_TIMEOUT: Duration = Duration::from_secs(1);
type GreetdHandle = Arc<GreetdConnection>;
type OperationGuard = OwnedMutexGuard<()>;

#[derive(Debug)]
struct GreetdConnection {
    transport: Mutex<GreetdTransport>,
    request_gate: Arc<Mutex<()>>,
    closed: AtomicBool,
}

impl GreetdConnection {
    fn new(transport: GreetdTransport) -> Self {
        Self {
            transport: Mutex::new(transport),
            request_gate: Arc::new(Mutex::new(())),
            closed: AtomicBool::new(false),
        }
    }

    async fn begin_request(
        &self,
        cancellation: &CancellationToken,
    ) -> Result<OwnedMutexGuard<()>, GreetdError> {
        let gate = Arc::clone(&self.request_gate).lock_owned().await;
        if self.closed.load(Ordering::Acquire) || cancellation.is_cancelled() {
            return Err(GreetdError::Cancelled);
        }
        Ok(gate)
    }

    fn finish_request(
        &self,
        cancellation: &CancellationToken,
        result: &Result<GreetdResponse, GreetdError>,
    ) {
        if cancellation.is_cancelled() || result.is_err() {
            self.closed.store(true, Ordering::Release);
        }
    }

    async fn cancel(&self) -> Result<GreetdResponse, GreetdError> {
        if self.closed.load(Ordering::Acquire) {
            return Ok(GreetdResponse::Success);
        }
        let _gate = Arc::clone(&self.request_gate).lock_owned().await;
        if self.closed.load(Ordering::Acquire) {
            return Ok(GreetdResponse::Success);
        }
        let mut transport = self.transport.lock().await;
        // Cancellation terminates this protocol session. Mark the connection closed before the
        // request starts so an aborted or malformed cancel exchange can never be reused.
        self.closed.store(true, Ordering::Release);
        let result = timeout(
            CANCEL_TIMEOUT,
            transport.cancel_session(&CancellationToken::new()),
        )
        .await;
        match result {
            Ok(result) => result,
            Err(_) => Err(GreetdError::Timeout),
        }
    }

    async fn create_session(
        &self,
        username: &str,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        let _gate = self.begin_request(cancellation).await?;
        let mut transport = self.transport.lock().await;
        let response = transport.create_session(username, cancellation).await;
        self.finish_request(cancellation, &response);
        response
    }

    async fn post_auth_message_response(
        &self,
        response: Option<&str>,
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        let _gate = self.begin_request(cancellation).await?;
        let mut transport = self.transport.lock().await;
        let response = transport
            .post_auth_message_response(response, cancellation)
            .await;
        self.finish_request(cancellation, &response);
        response
    }

    async fn start_session(
        &self,
        cmd: &[String],
        env: &[String],
        cancellation: &CancellationToken,
    ) -> Result<GreetdResponse, GreetdError> {
        let _gate = self.begin_request(cancellation).await?;
        let mut transport = self.transport.lock().await;
        let response = transport.start_session(cmd, env, cancellation).await;
        self.finish_request(cancellation, &response);
        response
    }
}

#[derive(Debug, Default)]
struct BackendState {
    auth: AuthStateMachine,
    greetd: Option<GreetdHandle>,
    cancellation: Option<CancellationToken>,
    caller: Option<String>,
    caller_watcher: Option<CancellationToken>,
}

#[derive(Clone, Debug)]
pub struct GreeterService {
    backend: Arc<Mutex<BackendState>>,
    handoff: Arc<Notify>,
    operation: Arc<Mutex<()>>,
    sessions: SessionCatalog,
    users: UserCatalog,
}

impl Default for GreeterService {
    fn default() -> Self {
        Self::new(Arc::new(Notify::new()))
    }
}

impl GreeterService {
    pub fn new(handoff: Arc<Notify>) -> Self {
        Self {
            backend: Arc::new(Mutex::new(BackendState::default())),
            handoff,
            operation: Arc::new(Mutex::new(())),
            sessions: SessionCatalog::default(),
            users: UserCatalog::default(),
        }
    }

    async fn lock_operation(&self) -> OperationGuard {
        Arc::clone(&self.operation).lock_owned().await
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum AuthenticationOutcome {
    WaitingForInput,
    Authenticated,
}

#[derive(Clone, Debug)]
struct StateSnapshot {
    attempt_id: String,
    state: String,
    detail: String,
}

impl StateSnapshot {
    fn from_auth(auth: &AuthStateMachine, attempt_id: &str) -> Self {
        Self {
            attempt_id: attempt_id.to_owned(),
            state: auth.state().as_str().to_owned(),
            detail: auth.detail().to_owned(),
        }
    }
}

#[interface(name = "io.mozais.Greeter1")]
impl GreeterService {
    async fn get_state(&self) -> (String, String) {
        let backend = self.backend.lock().await;
        (
            backend.auth.state().as_str().to_owned(),
            backend.auth.detail().to_owned(),
        )
    }

    async fn list_users(&self) -> fdo::Result<Vec<(String, String, String)>> {
        let users = self
            .users
            .list()
            .await
            .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        Ok(users
            .into_iter()
            .map(|user| (user.username, user.display_name, user.icon_path))
            .collect())
    }

    async fn list_sessions(&self) -> fdo::Result<Vec<(String, String, Vec<String>)>> {
        let sessions = self.sessions.clone();
        let sessions = tokio::task::spawn_blocking(move || sessions.list())
            .await
            .map_err(|error| fdo::Error::Failed(format!("session catalog task failed: {error}")))?
            .map_err(map_session_catalog_error)?;
        Ok(sessions
            .into_iter()
            .map(|session| (session.session_id, session.name, session.desktop_names))
            .collect())
    }

    async fn begin_authentication(
        &self,
        #[zbus(header)] header: Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        username: String,
    ) -> fdo::Result<String> {
        if username.trim().is_empty() {
            return Err(map_begin_authentication_error(
                BeginAuthenticationError::EmptyUsername,
            ));
        }
        let caller = header
            .sender()
            .map(ToString::to_string)
            .ok_or_else(|| fdo::Error::Failed("D-Bus caller has no unique name".to_owned()))?;
        let emitter = emitter.to_owned();
        self.cancel_active_transaction(None, None, None).await?;
        let _operation = self.lock_operation().await;

        let cancellation = CancellationToken::new();
        let watcher_token = CancellationToken::new();
        let (attempt_id, snapshot) = {
            let mut backend = self.backend.lock().await;
            let attempt_id = backend
                .auth
                .begin_authentication(username.clone())
                .map_err(map_begin_authentication_error)?;
            backend.cancellation = Some(cancellation.clone());
            backend.caller = Some(caller.clone());
            backend.caller_watcher = Some(watcher_token.clone());
            (
                attempt_id.clone(),
                StateSnapshot::from_auth(&backend.auth, &attempt_id),
            )
        };

        emit_state_best_effort(Some(&emitter), &snapshot).await;
        self.spawn_caller_watcher(
            emitter.connection().clone(),
            caller,
            attempt_id.clone(),
            watcher_token,
        );

        let transport = match GreetdTransport::connect(&cancellation).await {
            Ok(transport) => transport,
            Err(GreetdError::Cancelled) => return Err(cancelled_error()),
            Err(error) => {
                return Err(self
                    .fail_transaction_locked(&attempt_id, error, &emitter)
                    .await);
            }
        };
        let transport = Arc::new(GreetdConnection::new(transport));
        if !self
            .install_transport_locked(&attempt_id, Arc::clone(&transport))
            .await
        {
            return Err(cancelled_error());
        }

        let response = transport.create_session(&username, &cancellation).await;
        let response = match response {
            Ok(response) => response,
            Err(GreetdError::Cancelled) => return Err(cancelled_error()),
            Err(error) => {
                return Err(self
                    .fail_transaction_locked(&attempt_id, error, &emitter)
                    .await);
            }
        };

        self.consume_greetd_response_locked(
            transport,
            cancellation,
            emitter,
            &attempt_id,
            response,
        )
        .await?;
        Ok(attempt_id)
    }

    async fn respond(
        &self,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        attempt_id: String,
        response: String,
    ) -> fdo::Result<()> {
        let emitter = emitter.to_owned();
        let _operation = self.lock_operation().await;
        let (transport, cancellation, snapshot) = {
            let mut backend = self.backend.lock().await;
            validate_attempt(&backend.auth, &attempt_id)?;
            require_state(&backend.auth, AuthState::WaitingForInput)?;
            backend
                .auth
                .transition(StateEvent::ResponseSubmitted)
                .map_err(map_transition_error)?;
            let transport = backend
                .greetd
                .clone()
                .ok_or_else(|| fdo::Error::Failed("greetd transport is unavailable".to_owned()))?;
            let cancellation = backend.cancellation.clone().ok_or_else(|| {
                fdo::Error::Failed("authentication cancellation token is unavailable".to_owned())
            })?;
            (
                transport,
                cancellation,
                StateSnapshot::from_auth(&backend.auth, &attempt_id),
            )
        };
        emit_state_best_effort(Some(&emitter), &snapshot).await;

        let response = zeroize::Zeroizing::new(response);
        let next_response = transport
            .post_auth_message_response(Some(response.as_str()), &cancellation)
            .await;
        drop(response);

        let next_response = match next_response {
            Ok(response) => response,
            Err(GreetdError::Cancelled) => return Err(cancelled_error()),
            Err(error) => {
                return Err(self
                    .fail_transaction_locked(&attempt_id, error, &emitter)
                    .await);
            }
        };
        self.consume_greetd_response_locked(
            transport,
            cancellation,
            emitter,
            &attempt_id,
            next_response,
        )
        .await
        .map(|_| ())
    }

    async fn cancel(
        &self,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        attempt_id: String,
    ) -> fdo::Result<()> {
        let emitter = emitter.to_owned();
        self.cancel_active_transaction(Some(&attempt_id), None, Some(emitter))
            .await
    }

    async fn start_session(
        &self,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        attempt_id: String,
        session_id: String,
    ) -> fdo::Result<()> {
        let emitter = emitter.to_owned();
        let _operation = self.lock_operation().await;
        let snapshot = {
            let mut backend = self.backend.lock().await;
            validate_attempt(&backend.auth, &attempt_id)?;
            require_state(&backend.auth, AuthState::Authenticated)?;
            backend
                .auth
                .transition(StateEvent::StartSessionRequested)
                .map_err(map_transition_error)?;
            StateSnapshot::from_auth(&backend.auth, &attempt_id)
        };
        emit_state_best_effort(Some(&emitter), &snapshot).await;

        let sessions = self.sessions.clone();
        let session_id_for_lookup = session_id.clone();
        let session = tokio::task::spawn_blocking(move || sessions.find(&session_id_for_lookup))
            .await
            .map_err(|error| fdo::Error::Failed(format!("session catalog task failed: {error}")))?
            .map_err(map_session_catalog_error)?;
        let session = match session {
            Some(session) => session,
            None => {
                let detail = format!("session {session_id} is unavailable");
                let snapshot = self
                    .session_resolution_failed_locked(&attempt_id, detail.clone())
                    .await?;
                emit_state_best_effort(Some(&emitter), &snapshot).await;
                return Err(fdo::Error::InvalidArgs(detail));
            }
        };

        let (transport, cancellation, snapshot) = {
            let mut backend = self.backend.lock().await;
            validate_attempt(&backend.auth, &attempt_id)?;
            require_state(&backend.auth, AuthState::ResolvingSession)?;
            backend
                .auth
                .transition(StateEvent::SessionResolved)
                .map_err(map_transition_error)?;
            let transport = backend
                .greetd
                .clone()
                .ok_or_else(|| fdo::Error::Failed("greetd transport is unavailable".to_owned()))?;
            let cancellation = backend.cancellation.clone().ok_or_else(|| {
                fdo::Error::Failed("authentication cancellation token is unavailable".to_owned())
            })?;
            (
                transport,
                cancellation,
                StateSnapshot::from_auth(&backend.auth, &attempt_id),
            )
        };
        emit_state_best_effort(Some(&emitter), &snapshot).await;

        let environment = session_environment(&session);
        let response = transport
            .start_session(&session.exec, &environment, &cancellation)
            .await;
        let response = match response {
            Ok(response) => response,
            Err(GreetdError::Cancelled) => return Err(cancelled_error()),
            Err(error) => {
                return Err(self
                    .fail_transaction_locked(&attempt_id, error, &emitter)
                    .await);
            }
        };

        match response {
            GreetdResponse::Success => {
                let snapshot = {
                    let mut backend = self.backend.lock().await;
                    validate_attempt(&backend.auth, &attempt_id)?;
                    require_state(&backend.auth, AuthState::StartingSession)?;
                    backend
                        .auth
                        .transition(StateEvent::SessionStarted)
                        .map_err(map_transition_error)?;
                    detach_resources(&mut backend);
                    StateSnapshot::from_auth(&backend.auth, &attempt_id)
                };
                emit_state_best_effort(Some(&emitter), &snapshot).await;
                self.schedule_handoff_after_reply(emitter.connection().clone());
                Ok(())
            }
            GreetdResponse::Error {
                error_type,
                description,
            } => {
                let detail = display_detail(&format!("{error_type}: {description}"));
                let snapshot = self
                    .session_start_failed_locked(&attempt_id, detail.clone())
                    .await?;
                emit_state_best_effort(Some(&emitter), &snapshot).await;
                Err(fdo::Error::Failed(detail))
            }
            GreetdResponse::AuthMessage { .. } => Err(self
                .fail_transaction_locked(
                    &attempt_id,
                    GreetdError::UnexpectedResponse(
                        "greetd returned an authentication message while starting a session"
                            .to_owned(),
                    ),
                    &emitter,
                )
                .await),
        }
    }

    async fn power_action(&self, action: String) -> fdo::Result<()> {
        let method = match action.as_str() {
            "PowerOff" => "PowerOff",
            "Reboot" => "Reboot",
            "Suspend" => "Suspend",
            "Hibernate" => "Hibernate",
            _ => {
                return Err(fdo::Error::InvalidArgs(format!(
                    "unsupported power action: {action}"
                )));
            }
        };

        let _operation = self.lock_operation().await;
        let backend = self.backend.lock().await;
        if is_active_authentication_state(backend.auth.state()) {
            return Err(fdo::Error::Failed(
                "power action rejected while authentication is active".to_owned(),
            ));
        }
        drop(backend);

        let connection = zbus::Connection::system().await.map_err(|error| {
            fdo::Error::Failed(format!("could not connect to system D-Bus: {error}"))
        })?;
        let proxy = zbus::Proxy::new(
            &connection,
            "org.freedesktop.login1",
            "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager",
        )
        .await
        .map_err(|error| fdo::Error::Failed(format!("could not access logind: {error}")))?;
        proxy
            .call::<_, _, ()>(method, &(true,))
            .await
            .map_err(|error| fdo::Error::Failed(format!("power action failed: {error}")))
    }

    #[zbus(signal)]
    async fn prompt(
        emitter: &SignalEmitter<'_>,
        attempt_id: String,
        prompt_kind: String,
        text: String,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn state_changed(
        emitter: &SignalEmitter<'_>,
        attempt_id: String,
        state: String,
        detail: String,
    ) -> zbus::Result<()>;
}

impl GreeterService {
    fn schedule_handoff_after_reply(&self, connection: zbus::Connection) {
        let handoff = Arc::clone(&self.handoff);
        let activity = connection.monitor_activity();
        tokio::spawn(async move {
            activity.await;
            handoff.notify_waiters();
        });
    }

    fn spawn_caller_watcher(
        &self,
        connection: zbus::Connection,
        caller: String,
        attempt_id: String,
        watcher_token: CancellationToken,
    ) {
        let service = self.clone();
        tokio::spawn(async move {
            let proxy = match fdo::DBusProxy::new(&connection).await {
                Ok(proxy) => proxy,
                Err(error) => {
                    tracing::warn!(%error, "could not create D-Bus disconnect watcher");
                    service.handle_client_disconnect(&attempt_id, &caller).await;
                    return;
                }
            };
            let mut stream = match proxy
                .receive_name_owner_changed_with_args(&[(0, caller.as_str()), (2, "")])
                .await
            {
                Ok(stream) => stream,
                Err(error) => {
                    tracing::warn!(%error, "could not subscribe to D-Bus client disconnects");
                    service.handle_client_disconnect(&attempt_id, &caller).await;
                    return;
                }
            };
            let caller_name = match caller.as_str().try_into() {
                Ok(name) => name,
                Err(error) => {
                    tracing::warn!(%error, "D-Bus caller name was invalid");
                    return;
                }
            };
            if !proxy.name_has_owner(caller_name).await.unwrap_or(false) {
                service.handle_client_disconnect(&attempt_id, &caller).await;
                return;
            }
            tokio::select! {
                _ = watcher_token.cancelled() => {}
                _ = stream.next() => service.handle_client_disconnect(&attempt_id, &caller).await,
            }
        });
    }

    async fn handle_client_disconnect(&self, attempt_id: &str, caller: &str) {
        let _ = self
            .cancel_active_transaction(Some(attempt_id), Some(caller), None)
            .await;
    }

    async fn install_transport_locked(&self, attempt_id: &str, transport: GreetdHandle) -> bool {
        let mut backend = self.backend.lock().await;
        if backend.auth.is_current_attempt(attempt_id)
            && can_install_transport(backend.auth.state())
        {
            backend.greetd = Some(transport);
            true
        } else {
            false
        }
    }

    async fn cancel_active_transaction(
        &self,
        expected_attempt: Option<&str>,
        expected_caller: Option<&str>,
        emitter: Option<SignalEmitter<'static>>,
    ) -> fdo::Result<()> {
        let cancellation = {
            let backend = self.backend.lock().await;
            if let Some(expected_attempt) = expected_attempt {
                validate_attempt(&backend.auth, expected_attempt)?;
            }
            if let Some(expected_caller) = expected_caller
                && backend.caller.as_deref() != Some(expected_caller)
            {
                return Ok(());
            }
            if !is_active_authentication_state(backend.auth.state())
                || backend.auth.state() == AuthState::Cancelling
            {
                return Ok(());
            }
            backend.cancellation.clone()
        };
        if let Some(cancellation) = cancellation {
            cancellation.cancel();
        }
        let _operation = self.lock_operation().await;
        self.cancel_active_transaction_locked(expected_attempt, expected_caller, emitter)
            .await
    }

    async fn cancel_active_transaction_locked(
        &self,
        expected_attempt: Option<&str>,
        expected_caller: Option<&str>,
        emitter: Option<SignalEmitter<'static>>,
    ) -> fdo::Result<()> {
        let (attempt_id, transport, cancellation, watcher_token, snapshot) = {
            let mut backend = self.backend.lock().await;
            if let Some(expected_attempt) = expected_attempt {
                validate_attempt(&backend.auth, expected_attempt)?;
            }
            if let Some(expected_caller) = expected_caller
                && backend.caller.as_deref() != Some(expected_caller)
            {
                return Ok(());
            }
            if !is_active_authentication_state(backend.auth.state())
                || backend.auth.state() == AuthState::Cancelling
            {
                return Ok(());
            }
            let attempt_id = backend
                .auth
                .active_attempt_id()
                .unwrap_or_default()
                .to_owned();
            backend
                .auth
                .transition(StateEvent::CancelRequested)
                .map_err(map_transition_error)?;
            let snapshot = StateSnapshot::from_auth(&backend.auth, &attempt_id);
            let transport = backend.greetd.take();
            let cancellation = backend.cancellation.take();
            let watcher_token = backend.caller_watcher.take();
            backend.caller = None;
            (attempt_id, transport, cancellation, watcher_token, snapshot)
        };

        if let Some(token) = &cancellation {
            token.cancel();
        }
        if let Some(token) = &watcher_token {
            token.cancel();
        }
        emit_state_best_effort(emitter.as_ref(), &snapshot).await;

        let cancel_result = if let Some(transport) = transport {
            // If a request was interrupted, GreetdConnection has marked the socket closed and
            // this becomes a no-op. Otherwise the gate ensures cancel_session cannot be mixed
            // with another frame on the same socket.
            transport.cancel().await
        } else {
            Ok(GreetdResponse::Success)
        };

        let idle_snapshot = {
            let mut backend = self.backend.lock().await;
            if backend.auth.state() == AuthState::Cancelling {
                backend
                    .auth
                    .transition(StateEvent::CancellationFinished)
                    .map_err(map_transition_error)?;
                Some(StateSnapshot::from_auth(&backend.auth, &attempt_id))
            } else {
                None
            }
        };
        if let Some(snapshot) = idle_snapshot {
            emit_state_best_effort(emitter.as_ref(), &snapshot).await;
        }

        match cancel_result {
            Ok(GreetdResponse::Success) => Ok(()),
            Ok(GreetdResponse::Error {
                error_type,
                description,
            }) => Err(fdo::Error::Failed(format!(
                "could not cancel greetd session: {}",
                display_detail(&format!("{error_type}: {description}"))
            ))),
            Ok(GreetdResponse::AuthMessage { .. }) => Err(fdo::Error::Failed(
                "could not cancel greetd session: unexpected authentication message".to_owned(),
            )),
            Err(error) => Err(fdo::Error::Failed(format!(
                "could not cancel greetd session: {error}"
            ))),
        }
    }

    async fn consume_greetd_response_locked(
        &self,
        transport: GreetdHandle,
        cancellation: CancellationToken,
        emitter: SignalEmitter<'static>,
        attempt_id: &str,
        mut response: GreetdResponse,
    ) -> fdo::Result<AuthenticationOutcome> {
        loop {
            match response {
                GreetdResponse::Success => {
                    let snapshot = {
                        let mut backend = self.backend.lock().await;
                        validate_attempt(&backend.auth, attempt_id)?;
                        backend
                            .auth
                            .transition(StateEvent::AuthenticationSucceeded)
                            .map_err(map_transition_error)?;
                        StateSnapshot::from_auth(&backend.auth, attempt_id)
                    };
                    emit_state_best_effort(Some(&emitter), &snapshot).await;
                    return Ok(AuthenticationOutcome::Authenticated);
                }
                GreetdResponse::Error {
                    error_type,
                    description,
                } => {
                    let detail = display_detail(&format!("{error_type}: {description}"));
                    let snapshot = self
                        .authentication_failed_locked(attempt_id, detail.clone())
                        .await?;
                    emit_state_best_effort(Some(&emitter), &snapshot).await;
                    return Err(fdo::Error::Failed(detail));
                }
                GreetdResponse::AuthMessage {
                    auth_message_type,
                    auth_message,
                } => {
                    let snapshot = {
                        let mut backend = self.backend.lock().await;
                        validate_attempt(&backend.auth, attempt_id)?;
                        backend
                            .auth
                            .transition(StateEvent::AuthMessage)
                            .map_err(map_transition_error)?;
                        StateSnapshot::from_auth(&backend.auth, attempt_id)
                    };
                    emit_state_best_effort(Some(&emitter), &snapshot).await;
                    emit_prompt_best_effort(&emitter, attempt_id, &auth_message_type, auth_message)
                        .await;
                    match auth_message_type.as_str() {
                        "visible" | "secret" => {
                            let snapshot = {
                                let mut backend = self.backend.lock().await;
                                validate_attempt(&backend.auth, attempt_id)?;
                                backend
                                    .auth
                                    .transition(StateEvent::PromptNeedsInput)
                                    .map_err(map_transition_error)?;
                                StateSnapshot::from_auth(&backend.auth, attempt_id)
                            };
                            emit_state_best_effort(Some(&emitter), &snapshot).await;
                            return Ok(AuthenticationOutcome::WaitingForInput);
                        }
                        "info" | "error" => {
                            let snapshot = {
                                let mut backend = self.backend.lock().await;
                                validate_attempt(&backend.auth, attempt_id)?;
                                backend
                                    .auth
                                    .transition(StateEvent::PromptAutoResponse)
                                    .map_err(map_transition_error)?;
                                StateSnapshot::from_auth(&backend.auth, attempt_id)
                            };
                            emit_state_best_effort(Some(&emitter), &snapshot).await;
                            response = match transport
                                .post_auth_message_response(None, &cancellation)
                                .await
                            {
                                Ok(response) => response,
                                Err(GreetdError::Cancelled) => return Err(cancelled_error()),
                                Err(error) => {
                                    return Err(self
                                        .fail_transaction_locked(attempt_id, error, &emitter)
                                        .await);
                                }
                            };
                        }
                        _ => return Err(self
                            .fail_transaction_locked(
                                attempt_id,
                                GreetdError::UnexpectedResponse(format!(
                                    "unsupported authentication message type: {auth_message_type}"
                                )),
                                &emitter,
                            )
                            .await),
                    }
                }
            }
        }
    }

    async fn authentication_failed_locked(
        &self,
        attempt_id: &str,
        detail: String,
    ) -> fdo::Result<StateSnapshot> {
        let mut backend = self.backend.lock().await;
        validate_attempt(&backend.auth, attempt_id)?;
        backend
            .auth
            .transition(StateEvent::AuthenticationFailed { detail })
            .map_err(map_transition_error)?;
        detach_resources(&mut backend);
        Ok(StateSnapshot::from_auth(&backend.auth, attempt_id))
    }

    async fn session_resolution_failed_locked(
        &self,
        attempt_id: &str,
        detail: String,
    ) -> fdo::Result<StateSnapshot> {
        let mut backend = self.backend.lock().await;
        validate_attempt(&backend.auth, attempt_id)?;
        backend
            .auth
            .transition(StateEvent::SessionUnavailable { detail })
            .map_err(map_transition_error)?;
        Ok(StateSnapshot::from_auth(&backend.auth, attempt_id))
    }

    async fn session_start_failed_locked(
        &self,
        attempt_id: &str,
        detail: String,
    ) -> fdo::Result<StateSnapshot> {
        let mut backend = self.backend.lock().await;
        validate_attempt(&backend.auth, attempt_id)?;
        backend
            .auth
            .transition(StateEvent::SessionStartFailed { detail })
            .map_err(map_transition_error)?;
        detach_resources(&mut backend);
        Ok(StateSnapshot::from_auth(&backend.auth, attempt_id))
    }

    async fn fail_transaction_locked(
        &self,
        attempt_id: &str,
        error: GreetdError,
        emitter: &SignalEmitter<'_>,
    ) -> fdo::Error {
        if matches!(error, GreetdError::Cancelled) {
            return cancelled_error();
        }
        let detail = display_detail(&error.to_string());
        let snapshot = {
            let mut backend = self.backend.lock().await;
            if !backend.auth.is_current_attempt(attempt_id) {
                return cancelled_error();
            }
            backend
                .auth
                .transition(StateEvent::ProtocolFailure {
                    detail: detail.clone(),
                })
                .map_err(map_transition_error)
                .unwrap_or(AuthState::Failed);
            detach_resources(&mut backend);
            StateSnapshot::from_auth(&backend.auth, attempt_id)
        };
        emit_state_best_effort(Some(emitter), &snapshot).await;
        fdo::Error::Failed(detail)
    }
}

fn detach_resources(backend: &mut BackendState) {
    backend.greetd = None;
    if let Some(token) = backend.cancellation.take() {
        token.cancel();
    }
    if let Some(token) = backend.caller_watcher.take() {
        token.cancel();
    }
    backend.caller = None;
}

async fn emit_state_best_effort(emitter: Option<&SignalEmitter<'_>>, snapshot: &StateSnapshot) {
    let Some(emitter) = emitter else {
        return;
    };
    if let Err(error) = GreeterService::state_changed(
        emitter,
        snapshot.attempt_id.clone(),
        snapshot.state.clone(),
        snapshot.detail.clone(),
    )
    .await
    {
        tracing::debug!(%error, state = %snapshot.state, "could not emit StateChanged");
    }
}

async fn emit_prompt_best_effort(
    emitter: &SignalEmitter<'_>,
    attempt_id: &str,
    prompt_kind: &str,
    text: String,
) {
    if let Err(error) =
        GreeterService::prompt(emitter, attempt_id.to_owned(), prompt_kind.to_owned(), text).await
    {
        tracing::debug!(%error, "could not emit Prompt");
    }
}

fn validate_attempt(auth: &AuthStateMachine, attempt_id: &str) -> fdo::Result<()> {
    if auth.is_current_attempt(attempt_id) {
        Ok(())
    } else {
        Err(fdo::Error::Failed("stale or unknown attempt id".to_owned()))
    }
}

fn require_state(auth: &AuthStateMachine, expected: AuthState) -> fdo::Result<()> {
    if auth.state() == expected {
        Ok(())
    } else {
        Err(fdo::Error::Failed(format!(
            "operation is not valid in state {}",
            auth.state().as_str()
        )))
    }
}

fn is_active_authentication_state(state: AuthState) -> bool {
    match state {
        AuthState::CreatingSession
        | AuthState::PromptPending
        | AuthState::WaitingForInput
        | AuthState::SubmittingResponse
        | AuthState::Authenticated
        | AuthState::ResolvingSession
        | AuthState::StartingSession
        | AuthState::Cancelling => true,
        _ => false,
    }
}

fn can_install_transport(state: AuthState) -> bool {
    is_active_authentication_state(state) && state != AuthState::Cancelling
}

fn session_environment(session: &SessionEntry) -> Vec<String> {
    let mut environment = vec![
        "PATH=/usr/local/bin:/usr/bin:/bin".to_owned(),
        format!("XDG_SESSION_TYPE={}", session.session_type.as_str()),
    ];
    if let Some(desktop_name) = session.desktop_names.first() {
        environment.push(format!("XDG_SESSION_DESKTOP={desktop_name}"));
        environment.push(format!(
            "XDG_CURRENT_DESKTOP={}",
            session.desktop_names.join(":")
        ));
    }
    environment
}

fn display_detail(detail: &str) -> String {
    detail
        .chars()
        .filter(|character| !character.is_control() || *character == '\n' || *character == '\t')
        .take(512)
        .collect()
}

fn cancelled_error() -> fdo::Error {
    fdo::Error::Failed("authentication attempt was cancelled".to_owned())
}

fn map_begin_authentication_error(error: BeginAuthenticationError) -> fdo::Error {
    let detail = error.to_string();
    match error {
        BeginAuthenticationError::EmptyUsername => fdo::Error::InvalidArgs(detail),
        BeginAuthenticationError::InvalidState(_)
        | BeginAuthenticationError::AttemptIdExhausted => fdo::Error::Failed(detail),
    }
}

fn map_transition_error(error: crate::state::StateTransitionError) -> fdo::Error {
    fdo::Error::Failed(error.to_string())
}

fn map_session_catalog_error(error: SessionCatalogError) -> fdo::Error {
    fdo::Error::Failed(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::{AuthState, can_install_transport, is_active_authentication_state};

    #[test]
    fn cancelling_is_not_a_transport_installation_state() {
        assert!(is_active_authentication_state(AuthState::Cancelling));
        assert!(!can_install_transport(AuthState::Cancelling));
        assert!(can_install_transport(AuthState::CreatingSession));
    }

    #[cfg(feature = "mock")]
    #[tokio::test]
    async fn cancelling_closes_the_greetd_connection() {
        let cancellation = tokio_util::sync::CancellationToken::new();
        let transport = crate::greetd::GreetdTransport::connect(&cancellation)
            .await
            .expect("mock transport should connect");
        let connection = super::GreetdConnection::new(transport);

        assert!(matches!(
            connection.cancel().await,
            Ok(crate::greetd::GreetdResponse::Success)
        ));
        assert!(connection.closed.load(std::sync::atomic::Ordering::Acquire));
    }
}
