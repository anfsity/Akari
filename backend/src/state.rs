//! Authentication state and transition rules for one greetd transaction.
//!
//! The state machine is independent from D-Bus and socket I/O. Callers first
//! validate external input, then apply a [`StateEvent`]; invalid events are
//! rejected without mutating the machine.

use thiserror::Error;

/// Public authentication phase exposed through the Greeter1 D-Bus interface.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum AuthState {
    /// No authentication transaction is active.
    #[default]
    Idle,
    /// The backend is waiting for greetd's first response.
    CreatingSession,
    /// A greetd authentication message is being classified by the backend.
    PromptPending,
    /// The UI must provide a response to a visible or secret prompt.
    WaitingForInput,
    /// A UI response, or an automatic empty response, is being sent to greetd.
    SubmittingResponse,
    /// Authentication succeeded and the backend is waiting for a session choice.
    Authenticated,
    /// The selected desktop session is being resolved and validated.
    ResolvingSession,
    /// The validated desktop command is being submitted to greetd.
    StartingSession,
    /// greetd accepted the session start and the greeter is about to exit.
    HandingOff,
    /// The active greetd transaction is being cancelled.
    Cancelling,
    /// The transaction failed; display-safe context is retained in the detail field.
    Failed,
}

impl AuthState {
    /// Returns the stable wire representation used by D-Bus replies and signals.
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

    pub const fn is_active(self) -> bool {
        match self {
            Self::CreatingSession
            | Self::PromptPending
            | Self::WaitingForInput
            | Self::SubmittingResponse
            | Self::Authenticated
            | Self::ResolvingSession
            | Self::StartingSession => true,
            Self::Idle | Self::HandingOff | Self::Cancelling | Self::Failed => false,
        }
    }
}

/// Events accepted by [`AuthStateMachine::transition`].
///
/// Transport responses and D-Bus operations are interpreted by the service
/// before they are converted into these state-machine events.
#[derive(Debug)]
pub enum StateEvent {
    /// Starts a new authentication transaction from [`AuthState::Idle`] or [`AuthState::Failed`].
    BeginAuthentication,
    /// Indicates that greetd returned an authentication message.
    AuthMessage,
    /// Leaves a pending prompt waiting for user input.
    PromptNeedsInput,
    /// Leaves a pending informational or error prompt with an empty response queued.
    PromptAutoResponse,
    /// Indicates that the UI response was accepted for transmission.
    ResponseSubmitted,
    /// Indicates that greetd completed authentication successfully.
    AuthenticationSucceeded,
    /// Records a display-safe authentication failure.
    AuthenticationFailed { detail: String },
    /// Records a retryable credential rejection that restarts the greetd session.
    CredentialRejected { detail: String },
    /// Begins resolution of the session selected by the UI.
    StartSessionRequested,
    /// Keeps authentication available when the selected session is unavailable.
    SessionUnavailable { detail: String },
    /// Indicates that the selected session passed backend validation.
    SessionResolved,
    /// Indicates that greetd accepted the session start request.
    SessionStarted,
    /// Records a display-safe session-start failure.
    SessionStartFailed { detail: String },
    /// Starts cancellation of the current transaction.
    CancelRequested,
    /// Completes cancellation and returns the machine to [`AuthState::Idle`].
    CancellationFinished,
    /// Converts a transport or protocol failure into [`AuthState::Failed`].
    ProtocolFailure { detail: String },
}

/// Errors that can prevent a new authentication transaction from starting.
#[derive(Debug, Error, Eq, PartialEq)]
pub enum BeginAuthenticationError {
    #[error("authentication cannot begin in state {0:?}")]
    InvalidState(AuthState),
    #[error("attempt id sequence is exhausted")]
    AttemptIdExhausted,
}

impl StateEvent {
    const fn get_name(&self) -> &'static str {
        match self {
            Self::BeginAuthentication => "BeginAuthentication",
            Self::AuthMessage => "AuthMessage",
            Self::PromptNeedsInput => "PromptNeedsInput",
            Self::PromptAutoResponse => "PromptAutoResponse",
            Self::ResponseSubmitted => "ResponseSubmitted",
            Self::AuthenticationSucceeded => "AuthenticationSucceeded",
            Self::AuthenticationFailed { .. } => "AuthenticationFailed",
            Self::CredentialRejected { .. } => "CredentialRejected",
            Self::StartSessionRequested => "StartSessionRequested",
            Self::SessionUnavailable { .. } => "SessionUnavailable",
            Self::SessionResolved => "SessionResolved",
            Self::SessionStarted => "SessionStarted",
            Self::SessionStartFailed { .. } => "SessionStartFailed",
            Self::CancelRequested => "CancelRequested",
            Self::CancellationFinished => "CancellationFinished",
            Self::ProtocolFailure { .. } => "ProtocolFailure",
        }
    }
}

/// Error returned when an event is not valid for the current authentication phase.
#[derive(Debug, Error, Eq, PartialEq)]
pub enum StateTransitionError {
    #[error("event {event} is invalid in state {state:?}")]
    Invalid {
        state: AuthState,
        event: &'static str,
    },
}

/// Owns the authentication phase, display-safe failure detail, and active attempt token.
///
/// There is at most one active attempt. Terminal and cancellation states
/// invalidate that attempt so delayed D-Bus calls cannot operate on an older
/// greetd transaction.
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
    pub fn get_state(&self) -> AuthState {
        self.state
    }

    pub fn get_detail(&self) -> &str {
        &self.detail
    }

    pub fn find_active_attempt_id(&self) -> Option<&str> {
        self.active_attempt
            .as_ref()
            .map(|attempt| attempt.id.as_str())
    }

    pub fn is_current_attempt(&self, attempt_id: &str) -> bool {
        self.find_active_attempt_id() == Some(attempt_id)
    }

    pub fn find_active_username(&self) -> Option<&str> {
        self.active_attempt
            .as_ref()
            .map(|attempt| attempt.username.as_str())
    }

    /// Starts authentication for `username` and returns its new monotonic attempt ID.
    ///
    /// Callers must validate `username` and finish cancelling any active attempt
    /// before starting a replacement transaction. A failed transaction can start
    /// a new attempt directly, while a handoff already in progress cannot be
    /// replaced.
    ///
    /// # Errors
    ///
    /// Returns [`BeginAuthenticationError::InvalidState`] when an attempt or
    /// handoff is still active, or [`BeginAuthenticationError::AttemptIdExhausted`]
    /// if the counter cannot be incremented.
    pub fn begin_authentication(
        &mut self,
        username: String,
    ) -> Result<String, BeginAuthenticationError> {
        debug_assert!(
            !username.trim().is_empty(),
            "caller validates non-blank username"
        );

        if !matches!(self.state, AuthState::Idle | AuthState::Failed) {
            return Err(BeginAuthenticationError::InvalidState(self.state));
        }

        let next_attempt_number = self
            .next_attempt_number
            .checked_add(1)
            .ok_or(BeginAuthenticationError::AttemptIdExhausted)?;

        self.transition(StateEvent::BeginAuthentication)
            .expect("Idle or Failed must accept BeginAuthentication");

        let attempt_id = format!("attempt-{next_attempt_number:016x}");
        self.next_attempt_number = next_attempt_number;
        self.active_attempt = Some(ActiveAttempt {
            id: attempt_id.clone(),
            username,
        });

        Ok(attempt_id)
    }

    /// Applies one event and returns the resulting state.
    ///
    /// Invalid events return [`StateTransitionError`] and leave the state,
    /// active attempt, and detail unchanged. Successful transitions maintain
    /// the attempt invalidation and failure-detail rules of the public contract.
    pub fn transition(&mut self, event: StateEvent) -> Result<AuthState, StateTransitionError> {
        use AuthState::*;
        use StateEvent::*;

        let current = self.state;
        let event_name = event.get_name();

        let (next_state, new_detail) = match (current, event) {
            (Idle | Failed, BeginAuthentication) => (CreatingSession, None),

            (CreatingSession | SubmittingResponse, AuthMessage) => (PromptPending, None),
            (PromptPending, PromptNeedsInput) => (WaitingForInput, None),
            (PromptPending, PromptAutoResponse) | (WaitingForInput, ResponseSubmitted) => {
                (SubmittingResponse, None)
            }

            (CreatingSession | SubmittingResponse, AuthenticationSucceeded) => {
                (Authenticated, None)
            }
            (CreatingSession | SubmittingResponse, AuthenticationFailed { detail }) => {
                (Failed, Some(detail))
            }
            // A rejected credential keeps the attempt alive: the backend
            // restarts the greetd session so the user can try again.
            (SubmittingResponse, CredentialRejected { detail }) => (CreatingSession, Some(detail)),

            (Authenticated, StartSessionRequested) => (ResolvingSession, None),
            (ResolvingSession, SessionUnavailable { detail }) => (Authenticated, Some(detail)),
            (ResolvingSession, SessionResolved) => (StartingSession, None),
            (StartingSession, SessionStarted) => (HandingOff, None),
            (StartingSession, SessionStartFailed { detail }) => (Failed, Some(detail)),

            (s, CancelRequested) if s.is_active() => (Cancelling, None),
            (Cancelling, CancellationFinished) => (Idle, None),
            (s, ProtocolFailure { detail }) if s.is_active() => (Failed, Some(detail)),

            _ => {
                return Err(StateTransitionError::Invalid {
                    state: current,
                    event: event_name,
                });
            }
        };

        self.state = next_state;
        self.detail = new_detail.unwrap_or_default();
        if !next_state.is_active() {
            self.active_attempt = None;
        }

        Ok(next_state)
    }
}

#[cfg(test)]
mod tests {
    use super::{
        AuthState, AuthStateMachine, BeginAuthenticationError, StateEvent, StateTransitionError,
    };

    #[test]
    fn default_is_idle() {
        let machine = AuthStateMachine::default();

        assert_eq!(machine.get_state(), AuthState::Idle);
        assert_eq!(machine.get_detail(), "");
    }

    #[test]
    fn state_names_match_wire_values() {
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
    fn state_lifecycle_properties() {
        let active = [
            AuthState::CreatingSession,
            AuthState::PromptPending,
            AuthState::WaitingForInput,
            AuthState::SubmittingResponse,
            AuthState::Authenticated,
            AuthState::ResolvingSession,
            AuthState::StartingSession,
        ];
        for state in active {
            assert!(state.is_active(), "{state:?} should be active");
        }

        for state in [
            AuthState::Idle,
            AuthState::HandingOff,
            AuthState::Cancelling,
            AuthState::Failed,
        ] {
            assert!(!state.is_active(), "{state:?} should be inactive");
        }
    }

    #[test]
    fn protocol_failure_sets_detail() {
        let mut machine = authenticated_machine();

        machine
            .transition(StateEvent::ProtocolFailure {
                detail: "protocol failure".to_owned(),
            })
            .unwrap();
        assert_eq!(machine.get_state(), AuthState::Failed);
        assert_eq!(machine.get_detail(), "protocol failure");
    }

    #[test]
    fn auth_flow_reaches_handoff() {
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

        assert_eq!(machine.get_state(), AuthState::HandingOff);
        assert_eq!(machine.get_detail(), "");
    }

    #[test]
    fn info_prompt_auto_submits() {
        let mut machine = AuthStateMachine::default();

        machine.transition(StateEvent::BeginAuthentication).unwrap();
        machine.transition(StateEvent::AuthMessage).unwrap();
        machine.transition(StateEvent::PromptAutoResponse).unwrap();

        assert_eq!(machine.get_state(), AuthState::SubmittingResponse);
    }

    #[test]
    fn failed_state_accepts_new_authentication() {
        let mut machine = AuthStateMachine::default();

        machine.begin_authentication("alice".to_owned()).unwrap();
        machine
            .transition(StateEvent::AuthenticationFailed {
                detail: "authentication failed".to_owned(),
            })
            .unwrap();
        let next_id = machine.begin_authentication("bob".to_owned()).unwrap();

        assert_eq!(machine.get_state(), AuthState::CreatingSession);
        assert_eq!(machine.get_detail(), "");
        assert!(machine.is_current_attempt(&next_id));
        assert_eq!(machine.find_active_username(), Some("bob"));
    }

    #[test]
    fn invalid_transition_is_atomic() {
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
        assert_eq!(machine.get_state(), AuthState::Idle);
        assert_eq!(machine.get_detail(), "");
    }

    #[test]
    fn cancellation_returns_to_idle() {
        let mut machine = AuthStateMachine::default();

        let attempt_id = machine.begin_authentication("alice".to_owned()).unwrap();
        machine.transition(StateEvent::CancelRequested).unwrap();
        assert!(!machine.is_current_attempt(&attempt_id));
        machine
            .transition(StateEvent::CancellationFinished)
            .unwrap();

        assert_eq!(machine.get_state(), AuthState::Idle);
        assert_eq!(machine.get_detail(), "");
    }

    #[test]
    fn begin_requires_prior_cancellation_and_issues_monotonic_ids() {
        let mut machine = AuthStateMachine::default();

        let first_id = machine.begin_authentication("alice".to_owned()).unwrap();
        assert_eq!(first_id, "attempt-0000000000000001");
        assert!(machine.is_current_attempt(&first_id));
        assert_eq!(machine.find_active_username(), Some("alice"));
        assert_eq!(machine.get_state(), AuthState::CreatingSession);

        assert_eq!(
            machine.begin_authentication("bob".to_owned()),
            Err(BeginAuthenticationError::InvalidState(
                AuthState::CreatingSession
            ))
        );

        machine.transition(StateEvent::CancelRequested).unwrap();
        machine
            .transition(StateEvent::CancellationFinished)
            .unwrap();
        let second_id = machine.begin_authentication("bob".to_owned()).unwrap();

        assert_eq!(second_id, "attempt-0000000000000002");
        assert_ne!(first_id, second_id);
        assert!(!machine.is_current_attempt(&first_id));
        assert!(machine.is_current_attempt(&second_id));
        assert_eq!(machine.find_active_username(), Some("bob"));
        assert_eq!(machine.get_state(), AuthState::CreatingSession);
    }

    #[test]
    fn failure_invalidates_attempt() {
        let mut machine = AuthStateMachine::default();
        let attempt_id = machine.begin_authentication("alice".to_owned()).unwrap();

        machine
            .transition(StateEvent::AuthenticationFailed {
                detail: "authentication failed".to_owned(),
            })
            .unwrap();

        assert_eq!(machine.get_state(), AuthState::Failed);
        assert!(!machine.is_current_attempt(&attempt_id));
        assert_eq!(machine.find_active_attempt_id(), None);
    }

    #[test]
    fn credential_rejection_retains_attempt() {
        let mut machine = AuthStateMachine::default();
        let attempt_id = machine.begin_authentication("alice".to_owned()).unwrap();
        machine.transition(StateEvent::AuthMessage).unwrap();
        machine.transition(StateEvent::PromptNeedsInput).unwrap();
        machine.transition(StateEvent::ResponseSubmitted).unwrap();

        machine
            .transition(StateEvent::CredentialRejected {
                detail: "auth_error: authentication failed".to_owned(),
            })
            .unwrap();

        assert_eq!(machine.get_state(), AuthState::CreatingSession);
        assert_eq!(machine.get_detail(), "auth_error: authentication failed");
        assert!(machine.is_current_attempt(&attempt_id));
        assert_eq!(machine.find_active_username(), Some("alice"));
    }

    #[test]
    fn credential_rejection_requires_submitted_response() {
        let mut machine = AuthStateMachine::default();
        machine.begin_authentication("alice".to_owned()).unwrap();

        assert!(
            machine
                .transition(StateEvent::CredentialRejected {
                    detail: "auth_error".to_owned(),
                })
                .is_err()
        );
        assert_eq!(machine.get_state(), AuthState::CreatingSession);
    }

    #[test]
    fn unavailable_session_returns_to_auth() {
        let mut machine = authenticated_machine();

        machine
            .transition(StateEvent::StartSessionRequested)
            .unwrap();
        machine
            .transition(StateEvent::SessionUnavailable {
                detail: "session is unavailable".to_owned(),
            })
            .unwrap();

        assert_eq!(machine.get_state(), AuthState::Authenticated);
        assert_eq!(machine.get_detail(), "session is unavailable");
    }

    #[test]
    fn protocol_and_start_failures_are_terminal() {
        let mut protocol_failure = AuthStateMachine::default();
        protocol_failure
            .begin_authentication("alice".to_owned())
            .unwrap();
        protocol_failure
            .transition(StateEvent::ProtocolFailure {
                detail: "socket closed".to_owned(),
            })
            .unwrap();
        assert_eq!(protocol_failure.get_state(), AuthState::Failed);
        assert_eq!(protocol_failure.get_detail(), "socket closed");

        let mut session_failure = authenticated_machine();
        session_failure
            .transition(StateEvent::StartSessionRequested)
            .unwrap();
        session_failure
            .transition(StateEvent::SessionResolved)
            .unwrap();
        session_failure
            .transition(StateEvent::SessionStartFailed {
                detail: "command failed".to_owned(),
            })
            .unwrap();
        assert_eq!(session_failure.get_state(), AuthState::Failed);
        assert_eq!(session_failure.get_detail(), "command failed");
        assert_eq!(session_failure.find_active_attempt_id(), None);
    }

    #[test]
    fn handoff_rejects_new_auth() {
        let mut machine = authenticated_machine();
        machine
            .transition(StateEvent::StartSessionRequested)
            .unwrap();
        machine.transition(StateEvent::SessionResolved).unwrap();
        machine.transition(StateEvent::SessionStarted).unwrap();

        assert_eq!(
            machine.begin_authentication("bob".to_owned()),
            Err(BeginAuthenticationError::InvalidState(
                AuthState::HandingOff
            ))
        );
    }

    #[test]
    fn exhausted_ids_leave_state_unchanged() {
        let mut machine = AuthStateMachine {
            next_attempt_number: u64::MAX,
            ..AuthStateMachine::default()
        };

        assert_eq!(
            machine.begin_authentication("alice".to_owned()),
            Err(BeginAuthenticationError::AttemptIdExhausted)
        );
        assert_eq!(machine.get_state(), AuthState::Idle);
        assert_eq!(machine.find_active_attempt_id(), None);
    }

    #[test]
    fn terminal_states_reject_events() {
        let mut machine = AuthStateMachine::default();
        machine.begin_authentication("alice".to_owned()).unwrap();
        machine
            .transition(StateEvent::ProtocolFailure {
                detail: "failure".to_owned(),
            })
            .unwrap();

        assert!(machine.transition(StateEvent::ResponseSubmitted).is_err());
        assert!(machine.transition(StateEvent::SessionResolved).is_err());
    }

    fn authenticated_machine() -> AuthStateMachine {
        let mut machine = AuthStateMachine::default();
        machine.begin_authentication("alice".to_owned()).unwrap();
        machine
            .transition(StateEvent::AuthenticationSucceeded)
            .unwrap();
        machine
    }
}
