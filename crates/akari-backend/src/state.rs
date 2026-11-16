//! Authentication state and transition rules for one greetd transaction.
//!
//! The state machine owns the active attempt and its stage-specific resources,
//! preventing callers from observing an active phase without its attempt
//! metadata or leaving attempt resources attached after termination.

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

/// Active attempt metadata paired with caller-owned lifecycle resources.
#[derive(Debug, Eq, PartialEq)]
pub struct ActiveAttempt<R = ()> {
    pub id: String,
    pub username: String,
    pub resources: R,
}

/// Active attempt and optional suspended transport yielded when cancelling.
#[derive(Debug, Eq, PartialEq)]
pub struct DetachedAttempt<R = (), T = ()> {
    pub attempt: ActiveAttempt<R>,
    pub transport: Option<T>,
}

/// Events accepted by [`AuthStateMachine::transition`].
///
/// Transport-extracting transitions (`submit_response`, `resolve_session`, and
/// `request_cancel`) and attempt creation (`begin_authentication`) have typed
/// methods on [`AuthStateMachine`] so suspended transports and detached
/// resources are returned directly without optional unwrapping.
#[derive(Debug)]
pub enum StateEvent<T = ()> {
    /// Indicates that greetd returned an authentication message.
    AuthMessage,
    /// Leaves a pending prompt waiting for user input with its transport.
    PromptNeedsInput(T),
    /// Leaves a pending informational or error prompt with an empty response queued.
    PromptAutoResponse,
    /// Indicates that greetd completed authentication successfully.
    AuthenticationSucceeded(T),
    /// Records a display-safe authentication failure.
    AuthenticationFailed { detail: String },
    /// Records a retryable credential rejection that restarts the greetd session.
    CredentialRejected { detail: String },
    /// Begins resolution of the session selected by the UI.
    StartSessionRequested,
    /// Keeps authentication available when the selected session is unavailable.
    SessionUnavailable { detail: String },
    /// Indicates that greetd accepted the session start request.
    SessionStarted,
    /// Records a display-safe session-start failure.
    SessionStartFailed { detail: String },
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

impl<T> StateEvent<T> {
    const fn get_name(&self) -> &'static str {
        match self {
            Self::AuthMessage => "AuthMessage",
            Self::PromptNeedsInput(_) => "PromptNeedsInput",
            Self::PromptAutoResponse => "PromptAutoResponse",
            Self::AuthenticationSucceeded(_) => "AuthenticationSucceeded",
            Self::AuthenticationFailed { .. } => "AuthenticationFailed",
            Self::CredentialRejected { .. } => "CredentialRejected",
            Self::StartSessionRequested => "StartSessionRequested",
            Self::SessionUnavailable { .. } => "SessionUnavailable",
            Self::SessionStarted => "SessionStarted",
            Self::SessionStartFailed { .. } => "SessionStartFailed",
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

#[derive(Debug)]
enum MachinePhase<R, T> {
    Idle,
    Failed {
        detail: String,
    },
    HandingOff,
    Cancelling,
    Active {
        stage: ActiveStage<T>,
        detail: String,
        attempt: ActiveAttempt<R>,
    },
}

#[derive(Debug)]
enum ActiveStage<T> {
    CreatingSession,
    PromptPending,
    WaitingForInput(T),
    SubmittingResponse,
    Authenticated(T),
    ResolvingSession(T),
    StartingSession,
}

impl<T> ActiveStage<T> {
    const fn as_auth_state(&self) -> AuthState {
        match self {
            Self::CreatingSession => AuthState::CreatingSession,
            Self::PromptPending => AuthState::PromptPending,
            Self::WaitingForInput(_) => AuthState::WaitingForInput,
            Self::SubmittingResponse => AuthState::SubmittingResponse,
            Self::Authenticated(_) => AuthState::Authenticated,
            Self::ResolvingSession(_) => AuthState::ResolvingSession,
            Self::StartingSession => AuthState::StartingSession,
        }
    }

    fn into_transport(self) -> Option<T> {
        match self {
            Self::WaitingForInput(transport)
            | Self::Authenticated(transport)
            | Self::ResolvingSession(transport) => Some(transport),
            Self::CreatingSession
            | Self::PromptPending
            | Self::SubmittingResponse
            | Self::StartingSession => None,
        }
    }
}

/// Owns the authentication phase, display-safe failure detail, active attempt,
/// and suspended transport under one invariant.
#[derive(Debug)]
pub struct AuthStateMachine<R = (), T = ()> {
    phase: MachinePhase<R, T>,
    next_attempt_number: u64,
}

impl<R, T> Default for AuthStateMachine<R, T> {
    fn default() -> Self {
        Self {
            phase: MachinePhase::Idle,
            next_attempt_number: 0,
        }
    }
}

impl<R, T> AuthStateMachine<R, T> {
    pub fn get_state(&self) -> AuthState {
        match &self.phase {
            MachinePhase::Idle => AuthState::Idle,
            MachinePhase::Failed { .. } => AuthState::Failed,
            MachinePhase::HandingOff => AuthState::HandingOff,
            MachinePhase::Cancelling => AuthState::Cancelling,
            MachinePhase::Active { stage, .. } => stage.as_auth_state(),
        }
    }

    pub fn get_detail(&self) -> &str {
        match &self.phase {
            MachinePhase::Failed { detail } | MachinePhase::Active { detail, .. } => detail,
            MachinePhase::Idle | MachinePhase::HandingOff | MachinePhase::Cancelling => "",
        }
    }

    pub fn get_active(&self) -> Option<&ActiveAttempt<R>> {
        match &self.phase {
            MachinePhase::Active { attempt, .. } => Some(attempt),
            MachinePhase::Idle
            | MachinePhase::Failed { .. }
            | MachinePhase::HandingOff
            | MachinePhase::Cancelling => None,
        }
    }

    pub fn find_active_attempt_id(&self) -> Option<&str> {
        self.get_active().map(|attempt| attempt.id.as_str())
    }

    pub fn is_current_attempt(&self, attempt_id: &str) -> bool {
        self.find_active_attempt_id() == Some(attempt_id)
    }

    /// Starts authentication for `username` and returns its new monotonic attempt ID.
    ///
    /// Callers must validate `username` and cancel any active attempt before
    /// starting a replacement transaction. A failed transaction can start a new
    /// attempt directly, while a handoff already in progress cannot be replaced.
    ///
    /// # Errors
    ///
    /// Returns [`BeginAuthenticationError::InvalidState`] when an attempt or
    /// handoff is still active, or [`BeginAuthenticationError::AttemptIdExhausted`]
    /// if the counter cannot be incremented.
    pub fn begin_authentication(
        &mut self,
        username: String,
        build_resources: impl FnOnce(&str) -> R,
    ) -> Result<String, BeginAuthenticationError> {
        debug_assert!(
            !username.trim().is_empty(),
            "caller validates non-blank username"
        );

        if !matches!(self.phase, MachinePhase::Idle | MachinePhase::Failed { .. }) {
            return Err(BeginAuthenticationError::InvalidState(self.get_state()));
        }

        let next_attempt_number = self
            .next_attempt_number
            .checked_add(1)
            .ok_or(BeginAuthenticationError::AttemptIdExhausted)?;

        let id = format!("attempt-{next_attempt_number:016x}");
        let resources = build_resources(&id);
        self.next_attempt_number = next_attempt_number;
        self.phase = MachinePhase::Active {
            stage: ActiveStage::CreatingSession,
            detail: String::new(),
            attempt: ActiveAttempt {
                id: id.clone(),
                username,
                resources,
            },
        };

        Ok(id)
    }

    /// Moves [`AuthState::WaitingForInput`] to [`AuthState::SubmittingResponse`]
    /// and yields the suspended transport.
    pub fn submit_response(&mut self) -> Result<T, StateTransitionError> {
        let current = self.get_state();
        let previous = std::mem::replace(&mut self.phase, MachinePhase::Idle);
        match previous {
            MachinePhase::Active {
                stage: ActiveStage::WaitingForInput(transport),
                attempt,
                ..
            } => {
                self.phase = MachinePhase::Active {
                    stage: ActiveStage::SubmittingResponse,
                    detail: String::new(),
                    attempt,
                };
                Ok(transport)
            }
            previous => {
                self.phase = previous;
                Err(StateTransitionError::Invalid {
                    state: current,
                    event: "ResponseSubmitted",
                })
            }
        }
    }

    /// Moves [`AuthState::ResolvingSession`] to [`AuthState::StartingSession`]
    /// and yields the active transport.
    pub fn resolve_session(&mut self) -> Result<T, StateTransitionError> {
        let current = self.get_state();
        let previous = std::mem::replace(&mut self.phase, MachinePhase::Idle);
        match previous {
            MachinePhase::Active {
                stage: ActiveStage::ResolvingSession(transport),
                attempt,
                ..
            } => {
                self.phase = MachinePhase::Active {
                    stage: ActiveStage::StartingSession,
                    detail: String::new(),
                    attempt,
                };
                Ok(transport)
            }
            previous => {
                self.phase = previous;
                Err(StateTransitionError::Invalid {
                    state: current,
                    event: "SessionResolved",
                })
            }
        }
    }

    /// Moves any active state to [`AuthState::Cancelling`] and returns the
    /// detached attempt and any suspended transport.
    pub fn request_cancel(&mut self) -> Result<DetachedAttempt<R, T>, StateTransitionError> {
        let current = self.get_state();
        let previous = std::mem::replace(&mut self.phase, MachinePhase::Idle);
        match previous {
            MachinePhase::Active { stage, attempt, .. } => {
                self.phase = MachinePhase::Cancelling;
                Ok(DetachedAttempt {
                    attempt,
                    transport: stage.into_transport(),
                })
            }
            previous => {
                self.phase = previous;
                Err(StateTransitionError::Invalid {
                    state: current,
                    event: "CancelRequested",
                })
            }
        }
    }

    /// Applies one event and returns the resulting state.
    ///
    /// Invalid events return [`StateTransitionError`] and leave the phase,
    /// active attempt, and detail unchanged. Transitions leaving active states
    /// drop the active attempt so stale resources cannot outlive termination.
    pub fn transition(&mut self, event: StateEvent<T>) -> Result<AuthState, StateTransitionError> {
        let current = self.get_state();
        let event_name = event.get_name();
        let previous = std::mem::replace(&mut self.phase, MachinePhase::Idle);

        match (previous, event) {
            (
                MachinePhase::Active {
                    stage: ActiveStage::CreatingSession | ActiveStage::SubmittingResponse,
                    attempt,
                    ..
                },
                StateEvent::AuthMessage,
            ) => {
                self.phase = MachinePhase::Active {
                    stage: ActiveStage::PromptPending,
                    detail: String::new(),
                    attempt,
                };
            }
            (
                MachinePhase::Active {
                    stage: ActiveStage::PromptPending,
                    attempt,
                    ..
                },
                StateEvent::PromptNeedsInput(transport),
            ) => {
                self.phase = MachinePhase::Active {
                    stage: ActiveStage::WaitingForInput(transport),
                    detail: String::new(),
                    attempt,
                };
            }
            (
                MachinePhase::Active {
                    stage: ActiveStage::PromptPending,
                    attempt,
                    ..
                },
                StateEvent::PromptAutoResponse,
            ) => {
                self.phase = MachinePhase::Active {
                    stage: ActiveStage::SubmittingResponse,
                    detail: String::new(),
                    attempt,
                };
            }
            (
                MachinePhase::Active {
                    stage: ActiveStage::CreatingSession | ActiveStage::SubmittingResponse,
                    attempt,
                    ..
                },
                StateEvent::AuthenticationSucceeded(transport),
            ) => {
                self.phase = MachinePhase::Active {
                    stage: ActiveStage::Authenticated(transport),
                    detail: String::new(),
                    attempt,
                };
            }
            (
                MachinePhase::Active {
                    stage: ActiveStage::CreatingSession | ActiveStage::SubmittingResponse,
                    ..
                },
                StateEvent::AuthenticationFailed { detail },
            ) => {
                self.phase = MachinePhase::Failed { detail };
            }
            // A rejected credential keeps the attempt alive: the backend
            // restarts the greetd session so the user can try again.
            (
                MachinePhase::Active {
                    stage: ActiveStage::SubmittingResponse,
                    attempt,
                    ..
                },
                StateEvent::CredentialRejected { detail },
            ) => {
                self.phase = MachinePhase::Active {
                    stage: ActiveStage::CreatingSession,
                    detail,
                    attempt,
                };
            }
            (
                MachinePhase::Active {
                    stage: ActiveStage::Authenticated(transport),
                    attempt,
                    ..
                },
                StateEvent::StartSessionRequested,
            ) => {
                self.phase = MachinePhase::Active {
                    stage: ActiveStage::ResolvingSession(transport),
                    detail: String::new(),
                    attempt,
                };
            }
            (
                MachinePhase::Active {
                    stage: ActiveStage::ResolvingSession(transport),
                    attempt,
                    ..
                },
                StateEvent::SessionUnavailable { detail },
            ) => {
                self.phase = MachinePhase::Active {
                    stage: ActiveStage::Authenticated(transport),
                    detail,
                    attempt,
                };
            }
            (
                MachinePhase::Active {
                    stage: ActiveStage::StartingSession,
                    ..
                },
                StateEvent::SessionStarted,
            ) => {
                self.phase = MachinePhase::HandingOff;
            }
            (
                MachinePhase::Active {
                    stage: ActiveStage::StartingSession,
                    ..
                },
                StateEvent::SessionStartFailed { detail },
            ) => {
                self.phase = MachinePhase::Failed { detail };
            }
            (MachinePhase::Cancelling, StateEvent::CancellationFinished) => {
                self.phase = MachinePhase::Idle;
            }
            (MachinePhase::Active { .. }, StateEvent::ProtocolFailure { detail }) => {
                self.phase = MachinePhase::Failed { detail };
            }
            (previous, _) => {
                self.phase = previous;
                return Err(StateTransitionError::Invalid {
                    state: current,
                    event: event_name,
                });
            }
        }

        Ok(self.get_state())
    }
}

#[cfg(test)]
mod tests {
    use super::{
        AuthState, AuthStateMachine, BeginAuthenticationError, StateEvent, StateTransitionError,
    };

    fn begin(machine: &mut AuthStateMachine, username: &str) -> String {
        machine
            .begin_authentication(username.to_owned(), |_| ())
            .unwrap()
    }

    #[test]
    fn default_is_idle() {
        let machine = AuthStateMachine::<(), ()>::default();

        assert_eq!(machine.get_state(), AuthState::Idle);
        assert_eq!(machine.get_detail(), "");
        assert!(machine.get_active().is_none());
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
    fn protocol_failure_sets_detail_and_drops_attempt() {
        let mut machine = authenticated_machine();

        machine
            .transition(StateEvent::ProtocolFailure {
                detail: "protocol failure".to_owned(),
            })
            .unwrap();
        assert_eq!(machine.get_state(), AuthState::Failed);
        assert_eq!(machine.get_detail(), "protocol failure");
        assert!(machine.get_active().is_none());
    }

    #[test]
    fn auth_flow_reaches_handoff() {
        let mut machine = AuthStateMachine::default();
        begin(&mut machine, "alice");

        machine.transition(StateEvent::AuthMessage).unwrap();
        machine
            .transition(StateEvent::PromptNeedsInput(()))
            .unwrap();
        machine.submit_response().unwrap();
        machine
            .transition(StateEvent::AuthenticationSucceeded(()))
            .unwrap();
        machine
            .transition(StateEvent::StartSessionRequested)
            .unwrap();
        machine.resolve_session().unwrap();
        machine.transition(StateEvent::SessionStarted).unwrap();

        assert_eq!(machine.get_state(), AuthState::HandingOff);
        assert_eq!(machine.get_detail(), "");
        assert!(machine.get_active().is_none());
    }

    #[test]
    fn info_prompt_auto_submits() {
        let mut machine = AuthStateMachine::default();
        begin(&mut machine, "alice");

        machine.transition(StateEvent::AuthMessage).unwrap();
        machine.transition(StateEvent::PromptAutoResponse).unwrap();

        assert_eq!(machine.get_state(), AuthState::SubmittingResponse);
    }

    #[test]
    fn failed_state_accepts_new_authentication() {
        let mut machine = AuthStateMachine::default();
        begin(&mut machine, "alice");
        machine
            .transition(StateEvent::AuthenticationFailed {
                detail: "authentication failed".to_owned(),
            })
            .unwrap();
        let next_id = begin(&mut machine, "bob");

        assert_eq!(machine.get_state(), AuthState::CreatingSession);
        assert_eq!(machine.get_detail(), "");
        assert!(machine.is_current_attempt(&next_id));
        assert_eq!(machine.get_active().unwrap().username, "bob");
    }

    #[test]
    fn invalid_transition_is_atomic() {
        let mut machine = AuthStateMachine::<(), ()>::default();

        let error = machine.submit_response().unwrap_err();

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
    fn cancellation_returns_to_idle_and_yields_transport_only_when_suspended() {
        let mut machine = AuthStateMachine::<(), &'static str>::default();
        let attempt_id = machine
            .begin_authentication("alice".to_owned(), |_| ())
            .unwrap();
        machine.transition(StateEvent::AuthMessage).unwrap();
        machine
            .transition(StateEvent::PromptNeedsInput("transport"))
            .unwrap();

        let detached = machine.request_cancel().unwrap();
        assert_eq!(detached.attempt.id, attempt_id);
        assert_eq!(detached.transport, Some("transport"));
        assert!(!machine.is_current_attempt(&attempt_id));
        assert!(machine.get_active().is_none());

        machine
            .transition(StateEvent::CancellationFinished)
            .unwrap();

        assert_eq!(machine.get_state(), AuthState::Idle);
        assert_eq!(machine.get_detail(), "");
    }

    #[test]
    fn begin_requires_prior_cancellation_and_issues_monotonic_ids() {
        let mut machine = AuthStateMachine::default();

        let first_id = begin(&mut machine, "alice");
        assert_eq!(first_id, "attempt-0000000000000001");
        assert!(machine.is_current_attempt(&first_id));
        assert_eq!(machine.get_active().unwrap().username, "alice");
        assert_eq!(machine.get_state(), AuthState::CreatingSession);

        assert_eq!(
            machine.begin_authentication("bob".to_owned(), |_| ()),
            Err(BeginAuthenticationError::InvalidState(
                AuthState::CreatingSession
            ))
        );

        let detached = machine.request_cancel().unwrap();
        assert_eq!(detached.transport, None);
        machine
            .transition(StateEvent::CancellationFinished)
            .unwrap();
        let second_id = begin(&mut machine, "bob");

        assert_eq!(second_id, "attempt-0000000000000002");
        assert_ne!(first_id, second_id);
        assert!(!machine.is_current_attempt(&first_id));
        assert!(machine.is_current_attempt(&second_id));
        assert_eq!(machine.get_active().unwrap().username, "bob");
        assert_eq!(machine.get_state(), AuthState::CreatingSession);
    }

    #[test]
    fn failure_invalidates_attempt() {
        let mut machine = AuthStateMachine::default();
        let attempt_id = begin(&mut machine, "alice");

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
        let attempt_id = begin(&mut machine, "alice");
        machine.transition(StateEvent::AuthMessage).unwrap();
        machine
            .transition(StateEvent::PromptNeedsInput(()))
            .unwrap();
        machine.submit_response().unwrap();

        machine
            .transition(StateEvent::CredentialRejected {
                detail: "auth_error: authentication failed".to_owned(),
            })
            .unwrap();

        assert_eq!(machine.get_state(), AuthState::CreatingSession);
        assert_eq!(machine.get_detail(), "auth_error: authentication failed");
        assert!(machine.is_current_attempt(&attempt_id));
        assert_eq!(machine.get_active().unwrap().username, "alice");
    }

    #[test]
    fn credential_rejection_requires_submitted_response() {
        let mut machine = AuthStateMachine::default();
        begin(&mut machine, "alice");

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
        begin(&mut protocol_failure, "alice");
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
        session_failure.resolve_session().unwrap();
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
        machine.resolve_session().unwrap();
        machine.transition(StateEvent::SessionStarted).unwrap();

        assert_eq!(
            machine.begin_authentication("bob".to_owned(), |_| ()),
            Err(BeginAuthenticationError::InvalidState(
                AuthState::HandingOff
            ))
        );
    }

    #[test]
    fn exhausted_ids_leave_state_unchanged() {
        let mut machine = AuthStateMachine::<(), ()> {
            next_attempt_number: u64::MAX,
            ..AuthStateMachine::default()
        };

        assert_eq!(
            machine.begin_authentication("alice".to_owned(), |_| ()),
            Err(BeginAuthenticationError::AttemptIdExhausted)
        );
        assert_eq!(machine.get_state(), AuthState::Idle);
        assert_eq!(machine.find_active_attempt_id(), None);
    }

    #[test]
    fn terminal_states_reject_events() {
        let mut machine = AuthStateMachine::default();
        begin(&mut machine, "alice");
        machine
            .transition(StateEvent::ProtocolFailure {
                detail: "failure".to_owned(),
            })
            .unwrap();

        assert!(machine.submit_response().is_err());
        assert!(machine.resolve_session().is_err());
    }

    fn authenticated_machine() -> AuthStateMachine {
        let mut machine = AuthStateMachine::default();
        begin(&mut machine, "alice");
        machine
            .transition(StateEvent::AuthenticationSucceeded(()))
            .unwrap();
        machine
    }
}
