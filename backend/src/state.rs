use thiserror::Error;

#[allow(dead_code)]
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

#[allow(dead_code)]
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

#[allow(dead_code)]
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

#[allow(dead_code)]
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
}

#[allow(dead_code)]
impl AuthStateMachine {
    pub fn state(&self) -> AuthState {
        self.state
    }

    pub fn detail(&self) -> &str {
        &self.detail
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
    use super::{AuthState, AuthStateMachine, StateEvent, StateTransitionError};

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

        machine.transition(StateEvent::BeginAuthentication).unwrap();
        machine.transition(StateEvent::CancelRequested).unwrap();
        machine
            .transition(StateEvent::CancellationFinished)
            .unwrap();

        assert_eq!(machine.state(), AuthState::Idle);
        assert_eq!(machine.detail(), "");
    }
}
