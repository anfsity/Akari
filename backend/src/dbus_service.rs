use std::sync::Arc;

use tokio::sync::{Mutex, Notify};
use zbus::{fdo, interface, object_server::SignalEmitter};

use crate::{
    greetd::{GreetdError, GreetdResponse, GreetdTransport},
    session_catalog::{SessionCatalog, SessionCatalogError, SessionEntry},
    state::{AuthState, AuthStateMachine, BeginAuthenticationError, StateEvent},
    users::{UserCatalog, UserCatalogError},
};

pub const BUS_NAME: &str = "io.mozais.Greeter";
pub const OBJECT_PATH: &str = "/io/mozais/Greeter";

#[derive(Debug)]
struct BackendState {
    auth: AuthStateMachine,
    greetd: Option<GreetdTransport>,
    sessions: SessionCatalog,
    users: UserCatalog,
}

impl Default for BackendState {
    fn default() -> Self {
        Self {
            auth: AuthStateMachine::default(),
            greetd: None,
            sessions: SessionCatalog::default(),
            users: UserCatalog,
        }
    }
}

#[derive(Clone, Debug)]
pub struct GreeterService {
    backend: Arc<Mutex<BackendState>>,
    handoff: Arc<Notify>,
    operation: Arc<Mutex<()>>,
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
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum AuthenticationOutcome {
    WaitingForInput,
    Authenticated,
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
        let backend = self.backend.lock().await;
        backend.users.list().map_err(map_user_catalog_error)
    }

    async fn list_sessions(&self) -> fdo::Result<Vec<(String, String, Vec<String>)>> {
        let backend = self.backend.lock().await;
        Ok(backend
            .sessions
            .list()
            .map_err(map_session_catalog_error)?
            .into_iter()
            .map(|session| (session.session_id, session.name, session.desktop_names))
            .collect())
    }

    async fn begin_authentication(
        &self,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        username: String,
    ) -> fdo::Result<String> {
        let _operation = self.operation.lock().await;
        let mut backend = self.backend.lock().await;
        self.cancel_active_transaction(&mut backend, &emitter)
            .await?;

        let attempt_id = backend
            .auth
            .begin_authentication(username)
            .map_err(map_begin_authentication_error)?;
        emit_state(&emitter, &backend.auth, &attempt_id).await?;

        let mut transport = GreetdTransport::connect()
            .await
            .map_err(|error| self.fail_transaction(&mut backend, &emitter, &attempt_id, error))?;
        let username = backend
            .auth
            .active_username()
            .unwrap_or_default()
            .to_owned();
        let response = transport
            .create_session(&username)
            .await
            .map_err(|error| self.fail_transaction(&mut backend, &emitter, &attempt_id, error))?;
        backend.greetd = Some(transport);

        self.consume_greetd_response(&mut backend, &emitter, &attempt_id, response)
            .await?;

        Ok(attempt_id)
    }

    async fn respond(
        &self,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        attempt_id: String,
        response: String,
    ) -> fdo::Result<()> {
        let _operation = self.operation.lock().await;
        let mut backend = self.backend.lock().await;
        validate_attempt(&backend.auth, &attempt_id)?;
        require_state(&backend.auth, AuthState::WaitingForInput)?;

        backend
            .auth
            .transition(StateEvent::ResponseSubmitted)
            .map_err(map_transition_error)?;
        emit_state(&emitter, &backend.auth, &attempt_id).await?;

        let response = zeroize::Zeroizing::new(response);
        let next_response = {
            let Some(transport) = backend.greetd.as_mut() else {
                return Err(self.fail_transaction(
                    &mut backend,
                    &emitter,
                    &attempt_id,
                    GreetdError::UnexpectedResponse("greetd transport is unavailable".to_owned()),
                ));
            };
            transport
                .post_auth_message_response(Some(response.as_str()))
                .await
        };
        let next_response = next_response
            .map_err(|error| self.fail_transaction(&mut backend, &emitter, &attempt_id, error))?;
        drop(response);

        self.consume_greetd_response(&mut backend, &emitter, &attempt_id, next_response)
            .await
            .map(|_| ())
    }

    async fn cancel(
        &self,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        attempt_id: String,
    ) -> fdo::Result<()> {
        let _operation = self.operation.lock().await;
        let mut backend = self.backend.lock().await;
        validate_attempt(&backend.auth, &attempt_id)?;
        self.cancel_active_transaction(&mut backend, &emitter).await
    }

    async fn start_session(
        &self,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        attempt_id: String,
        session_id: String,
    ) -> fdo::Result<()> {
        let _operation = self.operation.lock().await;
        let mut backend = self.backend.lock().await;
        validate_attempt(&backend.auth, &attempt_id)?;
        require_state(&backend.auth, AuthState::Authenticated)?;

        backend
            .auth
            .transition(StateEvent::StartSessionRequested)
            .map_err(map_transition_error)?;
        emit_state(&emitter, &backend.auth, &attempt_id).await?;

        let session = match backend.sessions.find(&session_id) {
            Ok(Some(session)) => session,
            Ok(None) => {
                let detail = format!("session {session_id} is unavailable");
                backend
                    .auth
                    .transition(StateEvent::SessionUnavailable {
                        detail: detail.clone(),
                    })
                    .map_err(map_transition_error)?;
                emit_state(&emitter, &backend.auth, &attempt_id).await?;
                return Err(fdo::Error::InvalidArgs(detail));
            }
            Err(error) => {
                let detail = error.to_string();
                backend
                    .auth
                    .transition(StateEvent::SessionUnavailable {
                        detail: detail.clone(),
                    })
                    .map_err(map_transition_error)?;
                emit_state(&emitter, &backend.auth, &attempt_id).await?;
                return Err(fdo::Error::Failed(detail));
            }
        };

        backend
            .auth
            .transition(StateEvent::SessionResolved)
            .map_err(map_transition_error)?;
        emit_state(&emitter, &backend.auth, &attempt_id).await?;

        let environment = session_environment(&session);
        let response = {
            let Some(transport) = backend.greetd.as_mut() else {
                return Err(self.fail_transaction(
                    &mut backend,
                    &emitter,
                    &attempt_id,
                    GreetdError::UnexpectedResponse("greetd transport is unavailable".to_owned()),
                ));
            };
            transport.start_session(&session.exec, &environment).await
        };

        match response
            .map_err(|error| self.fail_transaction(&mut backend, &emitter, &attempt_id, error))?
        {
            GreetdResponse::Success => {
                backend
                    .auth
                    .transition(StateEvent::SessionStarted)
                    .map_err(map_transition_error)?;
                emit_state(&emitter, &backend.auth, &attempt_id).await?;
                backend.greetd = None;
                self.handoff.notify_waiters();
                Ok(())
            }
            GreetdResponse::Error {
                error_type,
                description,
            } => {
                let detail = display_detail(&format!("{error_type}: {description}"));
                backend
                    .auth
                    .transition(StateEvent::SessionStartFailed {
                        detail: detail.clone(),
                    })
                    .map_err(map_transition_error)?;
                emit_state(&emitter, &backend.auth, &attempt_id).await?;
                backend.greetd = None;
                Err(fdo::Error::Failed(detail))
            }
            GreetdResponse::AuthMessage { .. } => Err(self.fail_transaction(
                &mut backend,
                &emitter,
                &attempt_id,
                GreetdError::UnexpectedResponse(
                    "greetd returned an authentication message while starting a session".to_owned(),
                ),
            )),
        }
    }

    async fn power_action(&self, action: String) -> fdo::Result<()> {
        let _operation = self.operation.lock().await;
        {
            let backend = self.backend.lock().await;
            if is_active_authentication_state(backend.auth.state()) {
                return Err(fdo::Error::Failed(
                    "power action rejected while authentication is active".to_owned(),
                ));
            }
        }

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
    async fn cancel_active_transaction(
        &self,
        backend: &mut BackendState,
        emitter: &SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        if !is_active_authentication_state(backend.auth.state()) {
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
        emit_state(emitter, &backend.auth, &attempt_id).await?;

        let cancel_result = if let Some(transport) = backend.greetd.as_mut() {
            transport.cancel_session().await
        } else {
            Ok(GreetdResponse::Success)
        };

        backend.greetd = None;
        backend
            .auth
            .transition(StateEvent::CancellationFinished)
            .map_err(map_transition_error)?;
        emit_state(emitter, &backend.auth, &attempt_id).await?;

        cancel_result.map(|_| ()).map_err(|error| {
            fdo::Error::Failed(format!("could not cancel greetd session: {error}"))
        })
    }

    fn fail_transaction(
        &self,
        backend: &mut BackendState,
        emitter: &SignalEmitter<'_>,
        attempt_id: &str,
        error: GreetdError,
    ) -> fdo::Error {
        let detail = display_detail(&error.to_string());
        let transition = backend.auth.transition(StateEvent::ProtocolFailure {
            detail: detail.clone(),
        });
        backend.greetd = None;

        if transition.is_ok() {
            let emitter = emitter.to_owned();
            let state = backend.auth.state().as_str().to_owned();
            let detail_for_signal = backend.auth.detail().to_owned();
            let attempt_id = attempt_id.to_owned();
            tokio::spawn(async move {
                let _ =
                    GreeterService::state_changed(&emitter, attempt_id, state, detail_for_signal)
                        .await;
            });
        }

        fdo::Error::Failed(detail)
    }

    async fn consume_greetd_response(
        &self,
        backend: &mut BackendState,
        emitter: &SignalEmitter<'_>,
        attempt_id: &str,
        mut response: GreetdResponse,
    ) -> fdo::Result<AuthenticationOutcome> {
        loop {
            match response {
                GreetdResponse::Success => {
                    backend
                        .auth
                        .transition(StateEvent::AuthenticationSucceeded)
                        .map_err(map_transition_error)?;
                    emit_state(emitter, &backend.auth, attempt_id).await?;
                    return Ok(AuthenticationOutcome::Authenticated);
                }
                GreetdResponse::Error {
                    error_type,
                    description,
                } => {
                    let detail = display_detail(&format!("{error_type}: {description}"));
                    backend
                        .auth
                        .transition(StateEvent::AuthenticationFailed {
                            detail: detail.clone(),
                        })
                        .map_err(map_transition_error)?;
                    emit_state(emitter, &backend.auth, attempt_id).await?;
                    backend.greetd = None;
                    return Err(fdo::Error::Failed(detail));
                }
                GreetdResponse::AuthMessage {
                    auth_message_type,
                    auth_message,
                } => {
                    backend
                        .auth
                        .transition(StateEvent::AuthMessage)
                        .map_err(map_transition_error)?;
                    emit_state(emitter, &backend.auth, attempt_id).await?;

                    GreeterService::prompt(
                        emitter,
                        attempt_id.to_owned(),
                        auth_message_type.clone(),
                        auth_message,
                    )
                    .await
                    .map_err(map_signal_error)?;

                    match auth_message_type.as_str() {
                        "visible" | "secret" => {
                            backend
                                .auth
                                .transition(StateEvent::PromptNeedsInput)
                                .map_err(map_transition_error)?;
                            emit_state(emitter, &backend.auth, attempt_id).await?;
                            return Ok(AuthenticationOutcome::WaitingForInput);
                        }
                        "info" | "error" => {
                            backend
                                .auth
                                .transition(StateEvent::PromptAutoResponse)
                                .map_err(map_transition_error)?;
                            emit_state(emitter, &backend.auth, attempt_id).await?;

                            let next_response = {
                                let Some(transport) = backend.greetd.as_mut() else {
                                    return Err(self.fail_transaction(
                                        backend,
                                        emitter,
                                        attempt_id,
                                        GreetdError::UnexpectedResponse(
                                            "greetd transport is unavailable".to_owned(),
                                        ),
                                    ));
                                };
                                transport.post_auth_message_response(None).await
                            };
                            response = next_response.map_err(|error| {
                                self.fail_transaction(backend, emitter, attempt_id, error)
                            })?;
                        }
                        _ => {
                            return Err(self.fail_transaction(
                                backend,
                                emitter,
                                attempt_id,
                                GreetdError::UnexpectedResponse(format!(
                                    "unsupported authentication message type: {auth_message_type}"
                                )),
                            ));
                        }
                    }
                }
            }
        }
    }
}

async fn emit_state(
    emitter: &SignalEmitter<'_>,
    auth: &AuthStateMachine,
    attempt_id: &str,
) -> fdo::Result<()> {
    GreeterService::state_changed(
        emitter,
        attempt_id.to_owned(),
        auth.state().as_str().to_owned(),
        auth.detail().to_owned(),
    )
    .await
    .map_err(map_signal_error)
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
    let res = matches!(
        state,
        AuthState::CreatingSession
            | AuthState::PromptPending
            | AuthState::WaitingForInput
            | AuthState::SubmittingResponse
            | AuthState::Authenticated
            | AuthState::ResolvingSession
            | AuthState::StartingSession
            | AuthState::Cancelling
    );
    res
}

fn session_environment(session: &SessionEntry) -> Vec<String> {
    let mut environment = vec![format!(
        "XDG_SESSION_TYPE={}",
        session.session_type.as_str()
    )];
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

fn map_signal_error(error: zbus::Error) -> fdo::Error {
    fdo::Error::Failed(format!("could not emit D-Bus signal: {error}"))
}

fn map_session_catalog_error(error: SessionCatalogError) -> fdo::Error {
    fdo::Error::Failed(error.to_string())
}

fn map_user_catalog_error(error: UserCatalogError) -> fdo::Error {
    fdo::Error::Failed(error.to_string())
}
