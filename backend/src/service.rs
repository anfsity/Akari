//! D-Bus bridge between the Flutter greeter, greetd, session catalogs, and logind.

#[path = "auth.rs"]
mod auth;

use std::sync::Arc;

use tokio::sync::Notify;
use zbus::{
    fdo, interface,
    message::Header,
    object_server::{ResponseDispatchNotifier, SignalEmitter},
};

use self::auth::{AuthActorHandle, AuthActorTask};
use crate::{
    session_catalog::{SessionCatalog, SessionCatalogError},
    users::UserCatalog,
};

pub const BUS_NAME: &str = "io.mozais.Greeter";
pub const OBJECT_PATH: &str = "/io/mozais/Greeter";

#[derive(Clone, Debug)]
/// D-Bus service exposing user/session catalogs and serialized authentication.
pub struct GreeterService {
    auth: AuthActorHandle,
    handoff: Arc<Notify>,
    sessions: SessionCatalog,
    users: UserCatalog,
}

impl GreeterService {
    /// Creates a service whose successful session handoff notifies the backend runtime.
    pub fn new(handoff: Arc<Notify>) -> (Self, AuthActorTask) {
        let (auth, task) = AuthActorHandle::spawn();
        (
            Self {
                auth,
                handoff,
                sessions: SessionCatalog::default(),
                users: UserCatalog::default(),
            },
            task,
        )
    }

    fn owned_emitter(emitter: SignalEmitter<'_>) -> SignalEmitter<'static> {
        emitter.into_owned()
    }
}

#[interface(name = "io.mozais.Greeter1")]
impl GreeterService {
    async fn get_state(&self) -> fdo::Result<(String, String)> {
        self.auth.get_state()
    }

    async fn list_users(&self) -> fdo::Result<Vec<(String, String, String)>> {
        let users = self.users.list().await.map_err(|error| {
            tracing::warn!(operation = "ListUsers", error = ?error, "user catalog query failed");
            fdo::Error::Failed(error.to_string())
        })?;
        Ok(users
            .into_iter()
            .map(|user| (user.username, user.display_name, user.icon_path))
            .collect())
    }

    async fn list_sessions(&self) -> fdo::Result<Vec<(String, String, Vec<String>)>> {
        let sessions = self.sessions.clone();
        // Filesystem scans and executable checks are synchronous. Keep them
        // off the async executor and outside the authentication actor so state
        // queries and cancellation remain responsive during catalog work.
        let sessions = tokio::task::spawn_blocking(move || sessions.list())
            .await
            .map_err(|error| {
                tracing::error!(operation = "ListSessions", error = ?error, "session catalog task failed");
                fdo::Error::Failed(format!("session catalog task failed: {error}"))
            })?
            .map_err(map_session_error)?;
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
            return Err(fdo::Error::InvalidArgs(
                "username must not be empty".to_owned(),
            ));
        }
        let caller = get_caller(&header)?;
        self.auth
            .begin(caller, username, Self::owned_emitter(emitter))
            .await
    }

    async fn respond(
        &self,
        #[zbus(header)] header: Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        attempt_id: String,
        response: String,
    ) -> fdo::Result<()> {
        let caller = get_caller(&header)?;
        self.auth
            .respond(
                caller,
                attempt_id,
                zeroize::Zeroizing::new(response),
                Self::owned_emitter(emitter),
            )
            .await
    }

    async fn cancel(
        &self,
        #[zbus(header)] header: Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        attempt_id: String,
    ) -> fdo::Result<()> {
        let caller = get_caller(&header)?;
        self.auth
            .cancel(caller, attempt_id, Self::owned_emitter(emitter))
            .await
    }

    async fn start_session(
        &self,
        #[zbus(header)] header: Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        attempt_id: String,
        session_id: String,
    ) -> fdo::Result<ResponseDispatchNotifier<()>> {
        let caller = get_caller(&header)?;
        let emitter = Self::owned_emitter(emitter);
        self.auth
            .resolve_session(caller.clone(), attempt_id.clone(), emitter.clone())
            .await?;

        let sessions = self.sessions.clone();
        let lookup_id = session_id.clone();
        let session_result = tokio::task::spawn_blocking(move || sessions.find(&lookup_id)).await;
        let session_result = match session_result {
            Ok(result) => result,
            Err(error) => {
                tracing::error!(%attempt_id, %caller, operation = "ResolveSession", error = ?error, "session catalog task failed");
                let detail = format!("session catalog task failed: {error}");
                self.auth
                    .session_resolution_failed(caller, attempt_id, detail.clone(), emitter)
                    .await?;
                return Err(fdo::Error::Failed(detail));
            }
        };
        let session = match session_result {
            Ok(Some(session)) => session,
            Ok(None) => {
                let detail = format!("session {session_id} is unavailable");
                self.auth
                    .session_unavailable(caller, attempt_id, detail.clone(), emitter)
                    .await?;
                return Err(fdo::Error::InvalidArgs(detail));
            }
            Err(error) => {
                tracing::error!(%attempt_id, %caller, operation = "ResolveSession", error = ?error, "session catalog lookup failed");
                let detail = error.to_string();
                self.auth
                    .session_resolution_failed(caller, attempt_id, detail.clone(), emitter)
                    .await?;
                return Err(map_session_error(error));
            }
        };

        // The actor revalidates the attempt after the blocking catalog lookup,
        // so a stale lookup cannot start a session for a newer transaction.
        self.auth
            .start_session(caller, attempt_id, session, emitter)
            .await?;
        // HandingOff can be signalled before this method reply. Shutdown must
        // wait for zbus to dispatch the reply, otherwise a successful launch
        // can look like a disconnected/failed call to the frontend.
        let (response, dispatched) = ResponseDispatchNotifier::new(());
        let handoff = Arc::clone(&self.handoff);
        tokio::spawn(async move {
            dispatched.await;
            handoff.notify_one();
        });
        Ok(response)
    }

    async fn power_action(&self, action: String) -> fdo::Result<()> {
        let method = match action.as_str() {
            "PowerOff" | "Reboot" | "Suspend" | "Hibernate" => action.as_str(),
            _ => {
                return Err(fdo::Error::InvalidArgs(format!(
                    "unsupported power action: {action}"
                )));
            }
        };
        // logind runs outside the actor, but the lease blocks new authentication
        // until this call completes and releases on every return/error path.
        let _power_lease = self.auth.reserve_power().await?;

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

fn map_session_error(error: SessionCatalogError) -> fdo::Error {
    tracing::warn!(error = ?error, "session catalog query failed");
    fdo::Error::Failed(error.to_string())
}

fn get_caller(header: &Header<'_>) -> fdo::Result<String> {
    header
        .sender()
        .map(ToString::to_string)
        .ok_or_else(|| fdo::Error::AccessDenied("D-Bus caller has no unique name".to_owned()))
}
