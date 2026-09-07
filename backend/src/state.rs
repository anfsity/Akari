use thiserror::Error;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum AuthState {
    #[default]
    Idle,
    CreatingSession,
    PromptPending,
    WaitingForInput,
    SubmittingResponse,
    Authenticated,
    ResolvingSession,
    StartingSession,
    HandingOff,
    Cancelling,
    Failed,
}

impl AuthState {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Idle => "Idle",
            Self::CreatingSession => "CreatingSession",
            Self::PromptPending => "PromptPending",
            Self::WaitingForInput => "WaitingForInput",
            Self::SubmittingResponse => "SubmittingResponse",
            Self::Authenticated => "Authenticated",
            Self::ResolvingSession => "ResolvingSession",
            Self::StartingSession => "StartingSession",
            Self::HandingOff => "HandingOff",
            Self::Cancelling => "Cancelling",
            Self::Failed => "Failed",
        }
    }
}

#[derive(Debug)]
pub enum StateEvent {
    BeginAuthentication,
    AuthMessage,
    PromptNeedsInput,
    PromptAutoResponse,
    ResponseSubmitted,
    AuthenticationSucceeded,
    AuthenticationFailed { detail: String },
    StartSessionRequested,
    SessionUnavailable { detail: String },
    SessionResolved,
    SessionStarted,
    SessionStartFailed { detail: String },
    CancelRequested,
    CancellationFinished,
    Reset,
    ProtocolFailure { detail: String },
}

#[derive(Debug, Error, Eq, PartialEq)]
pub enum BeginAuthenticationError {
    #[error("username must not be empty")]
    EmptyUsername,
    #[error("authentication cannot begin in state {0:?}")]
    InvalidState(AuthState),
    #[error("attempt id sequence is exhausted")]
    AttemptIdExhausted,
}

impl StateEvent {
    const fn name(&self) -> &'static str {
        match self {
            Self::BeginAuthentication => "BeginAuthentication",
            Self::AuthMessage => "AuthMessage",
            Self::PromptNeedsInput => "PromptNeedsInput",
            Self::PromptAutoResponse => "PromptAutoResponse",
            Self::ResponseSubmitted => "ResponseSubmitted",
            Self::AuthenticationSucceeded => "AuthenticationSucceeded",
            Self::AuthenticationFailed { .. } => "AuthenticationFailed",
            Self::StartSessionRequested => "StartSessionRequested",
            Self::SessionUnavailable { .. } => "SessionUnavailable",
            Self::SessionResolved => "SessionResolved",
            Self::SessionStarted => "SessionStarted",
            Self::SessionStartFailed { .. } => "SessionStartFailed",
            Self::CancelRequested => "CancelRequested",
            Self::CancellationFinished => "CancellationFinished",
            Self::Reset => "Reset",
            Self::ProtocolFailure { .. } => "ProtocolFailure",
        }
    }
}

#[derive(Debug, Error, Eq, PartialEq)]
pub enum StateTransitionError {
    #[error("event {event} is invalid in state {state:?}")]
    Invalid {
        state: AuthState,
        event: &'static str,
    },
}

#[derive(Debug, Default)]
pub struct AuthStateMachine {
    state: AuthState,
    detail: String,
    active_attempt: Option<ActiveAttempt>,
    next_attempt_number: u64,
}

#[derive(Debug, Eq, PartialEq)]
struct ActiveAttempt {
    id: String,
    username: String,
}

impl AuthStateMachine {
    pub fn state(&self) -> AuthState {
        self.state
    }

    pub fn detail(&self) -> &str {
        &self.detail
    }

    pub fn active_attempt_id(&self) -> Option<&str> {
        self.active_attempt
            .as_ref()
            .map(|attempt| attempt.id.as_str())
    }

    pub fn active_username(&self) -> Option<&str> {
        self.active_attempt
            .as_ref()
            .map(|attempt| attempt.username.as_str())
    }

    pub fn is_current_attempt(&self, attempt_id: &str) -> bool {
        self.active_attempt_id() == Some(attempt_id)
    }

    pub fn begin_authentication(
        &mut self,
        username: String,
    ) -> Result<String, BeginAuthenticationError> {
        if username.trim().is_empty() {
            return Err(BeginAuthenticationError::EmptyUsername);
        }

        let next_attempt_number = self
            .next_attempt_number
            .checked_add(1)
            .ok_or(BeginAuthenticationError::AttemptIdExhausted)?;

        match self.state {
            AuthState::Idle => {}
            AuthState::Failed => {
                self.transition(StateEvent::Reset)
                    .expect("Failed must accept Reset");
            }
            AuthState::Cancelling => {
                self.transition(StateEvent::CancellationFinished)
                    .expect("Cancelling must accept CancellationFinished");
            }
            AuthState::CreatingSession
            | AuthState::PromptPending
            | AuthState::WaitingForInput
            | AuthState::SubmittingResponse
            | AuthState::Authenticated
            | AuthState::ResolvingSession
            | AuthState::StartingSession => {
                self.transition(StateEvent::CancelRequested)
                    .expect("active states must accept CancelRequested");
                self.transition(StateEvent::CancellationFinished)
                    .expect("Cancelling must accept CancellationFinished");
            }
            AuthState::HandingOff => {
                return Err(BeginAuthenticationError::InvalidState(
                    AuthState::HandingOff,
                ));
            }
        }

        self.transition(StateEvent::BeginAuthentication)
            .expect("Idle must accept BeginAuthentication");

        let attempt_id = format!("attempt-{next_attempt_number:016x}");
        self.next_attempt_number = next_attempt_number;
        self.active_attempt = Some(ActiveAttempt {
            id: attempt_id.clone(),
            username,
        });

        Ok(attempt_id)
    }

    pub fn transition(&mut self, event: StateEvent) -> Result<AuthState, StateTransitionError> {
        let previous_state = self.state;
        let next_state = match (&self.state, &event) {
            (AuthState::Idle, StateEvent::BeginAuthentication) => AuthState::CreatingSession,
            (AuthState::CreatingSession, StateEvent::AuthMessage)
            | (AuthState::SubmittingResponse, StateEvent::AuthMessage) => AuthState::PromptPending,
            (AuthState::PromptPending, StateEvent::PromptNeedsInput) => AuthState::WaitingForInput,
            (AuthState::PromptPending, StateEvent::PromptAutoResponse)
            | (AuthState::WaitingForInput, StateEvent::ResponseSubmitted) => {
                AuthState::SubmittingResponse
            }
            (AuthState::CreatingSession, StateEvent::AuthenticationSucceeded)
            | (AuthState::SubmittingResponse, StateEvent::AuthenticationSucceeded) => {
                AuthState::Authenticated
            }
            (AuthState::CreatingSession, StateEvent::AuthenticationFailed { .. })
            | (AuthState::SubmittingResponse, StateEvent::AuthenticationFailed { .. }) => {
                AuthState::Failed
            }
            (AuthState::Authenticated, StateEvent::StartSessionRequested) => {
                AuthState::ResolvingSession
            }
            (AuthState::ResolvingSession, StateEvent::SessionUnavailable { .. }) => {
                AuthState::Authenticated
            }
            (AuthState::ResolvingSession, StateEvent::SessionResolved) => {
                AuthState::StartingSession
            }
            (AuthState::StartingSession, StateEvent::SessionStarted) => AuthState::HandingOff,
            (AuthState::StartingSession, StateEvent::SessionStartFailed { .. }) => {
                AuthState::Failed
            }
            (
                AuthState::CreatingSession
                | AuthState::PromptPending
                | AuthState::WaitingForInput
                | AuthState::SubmittingResponse
                | AuthState::Authenticated
                | AuthState::ResolvingSession
                | AuthState::StartingSession,
                StateEvent::CancelRequested,
            ) => AuthState::Cancelling,
            (AuthState::Cancelling, StateEvent::CancellationFinished) => AuthState::Idle,
            (AuthState::Failed, StateEvent::Reset) => AuthState::Idle,
            (
                AuthState::CreatingSession
                | AuthState::PromptPending
                | AuthState::WaitingForInput
                | AuthState::SubmittingResponse
                | AuthState::Authenticated
                | AuthState::ResolvingSession
                | AuthState::StartingSession,
                StateEvent::ProtocolFailure { .. },
            ) => AuthState::Failed,
            _ => {
                return Err(StateTransitionError::Invalid {
                    state: self.state,
                    event: event.name(),
                });
            }
        };

        self.state = next_state;
        if matches!(
            next_state,
            AuthState::Cancelling | AuthState::Idle | AuthState::HandingOff | AuthState::Failed
        ) {
            self.active_attempt = None;
        }
        self.update_detail(previous_state, event);
        Ok(next_state)
    }

    fn update_detail(&mut self, previous_state: AuthState, event: StateEvent) {
        match event {
            StateEvent::AuthenticationFailed { detail }
            | StateEvent::SessionStartFailed { detail }
            | StateEvent::ProtocolFailure { detail }
            | StateEvent::SessionUnavailable { detail } => self.detail = detail,
            StateEvent::Reset if previous_state == AuthState::Failed => {}
            _ => self.detail.clear(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        AuthState, AuthStateMachine, BeginAuthenticationError, StateEvent, StateTransitionError,
    };

    #[test]
    fn default_state_is_idle() {
        let machine = AuthStateMachine::default();

        assert_eq!(machine.state(), AuthState::Idle);
        assert_eq!(machine.detail(), "");
    }

    #[test]
    fn state_names_match_the_dbus_contract() {
        let states = [
            (AuthState::Idle, "Idle"),
            (AuthState::CreatingSession, "CreatingSession"),
            (AuthState::PromptPending, "PromptPending"),
            (AuthState::WaitingForInput, "WaitingForInput"),
            (AuthState::SubmittingResponse, "SubmittingResponse"),
            (AuthState::Authenticated, "Authenticated"),
            (AuthState::ResolvingSession, "ResolvingSession"),
            (AuthState::StartingSession, "StartingSession"),
            (AuthState::HandingOff, "HandingOff"),
            (AuthState::Cancelling, "Cancelling"),
            (AuthState::Failed, "Failed"),
        ];

        for (state, expected_name) in states {
            assert_eq!(state.as_str(), expected_name);
        }
    }

    #[test]
    fn authentication_flow_reaches_handoff() {
        let mut machine = AuthStateMachine::default();

        for event in [
            StateEvent::BeginAuthentication,
            StateEvent::AuthMessage,
            StateEvent::PromptNeedsInput,
            StateEvent::ResponseSubmitted,
            StateEvent::AuthenticationSucceeded,
            StateEvent::StartSessionRequested,
            StateEvent::SessionResolved,
            StateEvent::SessionStarted,
        ] {
            machine.transition(event).unwrap();
        }

        assert_eq!(machine.state(), AuthState::HandingOff);
        assert_eq!(machine.detail(), "");
    }

    #[test]
    fn informational_prompt_automatically_submits() {
        let mut machine = AuthStateMachine::default();

        machine.transition(StateEvent::BeginAuthentication).unwrap();
        machine.transition(StateEvent::AuthMessage).unwrap();
        machine.transition(StateEvent::PromptAutoResponse).unwrap();

        assert_eq!(machine.state(), AuthState::SubmittingResponse);
    }

    #[test]
    fn failure_detail_is_retained_after_reset() {
        let mut machine = AuthStateMachine::default();

        machine.transition(StateEvent::BeginAuthentication).unwrap();
        machine
            .transition(StateEvent::AuthenticationFailed {
                detail: "authentication failed".to_owned(),
            })
            .unwrap();
        machine.transition(StateEvent::Reset).unwrap();

        assert_eq!(machine.state(), AuthState::Idle);
        assert_eq!(machine.detail(), "authentication failed");
    }

    #[test]
    fn invalid_transition_does_not_change_state() {
        let mut machine = AuthStateMachine::default();

        let error = machine
            .transition(StateEvent::ResponseSubmitted)
            .unwrap_err();

        assert_eq!(
            error,
            StateTransitionError::Invalid {
                state: AuthState::Idle,
                event: "ResponseSubmitted",
            }
        );
        assert_eq!(machine.state(), AuthState::Idle);
        assert_eq!(machine.detail(), "");
    }

    #[test]
    fn cancellation_returns_to_idle_and_clears_detail() {
        let mut machine = AuthStateMachine::default();

        let attempt_id = machine.begin_authentication("alice".to_owned()).unwrap();
        machine.transition(StateEvent::CancelRequested).unwrap();
        assert!(!machine.is_current_attempt(&attempt_id));
        machine
            .transition(StateEvent::CancellationFinished)
            .unwrap();

        assert_eq!(machine.state(), AuthState::Idle);
        assert_eq!(machine.detail(), "");
    }

    #[test]
    fn begin_authentication_replaces_the_active_attempt() {
        let mut machine = AuthStateMachine::default();

        let first_id = machine.begin_authentication("alice".to_owned()).unwrap();
        assert_eq!(first_id, "attempt-0000000000000001");
        assert!(machine.is_current_attempt(&first_id));
        assert_eq!(machine.active_username(), Some("alice"));
        assert_eq!(machine.state(), AuthState::CreatingSession);

        let second_id = machine.begin_authentication("bob".to_owned()).unwrap();

        assert_eq!(second_id, "attempt-0000000000000002");
        assert_ne!(first_id, second_id);
        assert!(!machine.is_current_attempt(&first_id));
        assert!(machine.is_current_attempt(&second_id));
        assert_eq!(machine.active_username(), Some("bob"));
        assert_eq!(machine.state(), AuthState::CreatingSession);
    }

    #[test]
    fn empty_username_does_not_create_an_attempt() {
        let mut machine = AuthStateMachine::default();

        let error = machine.begin_authentication("   ".to_owned()).unwrap_err();

        assert_eq!(error, BeginAuthenticationError::EmptyUsername);
        assert_eq!(machine.state(), AuthState::Idle);
        assert_eq!(machine.active_attempt_id(), None);
    }

    #[test]
    fn terminal_failure_invalidates_the_active_attempt() {
        let mut machine = AuthStateMachine::default();
        let attempt_id = machine.begin_authentication("alice".to_owned()).unwrap();

        machine
            .transition(StateEvent::AuthenticationFailed {
                detail: "authentication failed".to_owned(),
            })
            .unwrap();

        assert_eq!(machine.state(), AuthState::Failed);
        assert!(!machine.is_current_attempt(&attempt_id));
        assert_eq!(machine.active_attempt_id(), None);
    }
}
