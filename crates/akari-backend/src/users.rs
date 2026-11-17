//! User discovery through the system AccountsService D-Bus API.

use std::sync::Arc;

use thiserror::Error;
use tokio::sync::Mutex;
use zbus::{proxy, proxy::CacheProperties, zvariant::OwnedObjectPath};

#[proxy(
    default_service = "org.freedesktop.Accounts",
    default_path = "/org/freedesktop/Accounts",
    interface = "org.freedesktop.Accounts"
)]
trait AccountsService {
    fn list_cached_users(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
}

#[derive(Debug, Error)]
pub enum UserCatalogError {
    #[error("could not connect to the system D-Bus")]
    Connect(#[source] zbus::Error),
    #[error("could not call AccountsService.ListCachedUsers")]
    List(#[source] zbus::Error),
}

/// A user record exposed by the greeter catalog.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserEntry {
    pub username: String,
    pub display_name: String,
    pub icon_path: String,
}

/// Lazily shared system D-Bus connection. Closed connections are discarded
/// before the next query so long-lived callers do not keep leaking connections.
#[derive(Clone, Debug, Default)]
pub(crate) struct SystemBus {
    connection: Arc<Mutex<Option<zbus::Connection>>>,
}

impl SystemBus {
    pub(crate) async fn connect(&self) -> zbus::Result<zbus::Connection> {
        // Serialize only connection initialization/replacement. The returned
        // clone lets callers perform D-Bus I/O without holding this mutex.
        let mut cached = self.connection.lock().await;
        if let Some(connection) = cached.as_ref()
            && !connection.is_closed()
        {
            return Ok(connection.clone());
        }
        cached.take();
        let connection = zbus::Connection::system().await?;
        *cached = Some(connection.clone());
        Ok(connection)
    }
}

/// Reads login users from AccountsService without parsing NSS or passwd files.
///
/// User properties are fetched in a single `Properties.GetAll` call per user.
#[derive(Clone, Debug)]
pub struct UserCatalog {
    system_bus: SystemBus,
}

impl UserCatalog {
    pub(crate) fn new(system_bus: SystemBus) -> Self {
        Self { system_bus }
    }

    pub async fn list(&self) -> Result<Vec<UserEntry>, UserCatalogError> {
        let connection = self
            .system_bus
            .connect()
            .await
            .map_err(UserCatalogError::Connect)?;
        let accounts = AccountsServiceProxy::new(&connection)
            .await
            .map_err(UserCatalogError::List)?;
        let paths = accounts
            .list_cached_users()
            .await
            .map_err(UserCatalogError::List)?;

        let tasks = paths.iter().map(|path| read_user(&connection, path));
        let results = futures_util::future::join_all(tasks).await;

        let mut users = Vec::with_capacity(paths.len());
        for result in results {
            match result {
                Ok(Some(user)) => users.push(user),
                Ok(None) => {}
                Err(error) => {
                    tracing::warn!(error = ?error, "skipping unavailable AccountsService user");
                }
            }
        }
        users.sort_by(|left, right| left.username.cmp(&right.username));
        Ok(users)
    }
}

async fn read_user(
    connection: &zbus::Connection,
    path: &OwnedObjectPath,
) -> Result<Option<UserEntry>, UserObjectError> {
    let map_err = |source| UserObjectError {
        path: path.to_string(),
        source: Box::new(source),
    };

    let proxy = zbus::fdo::PropertiesProxy::builder(connection)
        .destination("org.freedesktop.Accounts")
        .map_err(map_err)?
        .path(path.as_ref())
        .map_err(map_err)?
        .cache_properties(CacheProperties::No)
        .build()
        .await
        .map_err(map_err)?;

    let properties = proxy
        .get_all(zbus::names::InterfaceName::from_static_str_unchecked(
            "org.freedesktop.Accounts.User",
        ))
        .await
        .map_err(|error| map_err(error.into()))?;

    let system_account = properties
        .get("SystemAccount")
        .ok_or_else(|| map_err(zbus::Error::MissingField))
        .and_then(|value| bool::try_from(value).map_err(|error| map_err(error.into())))?;
    if system_account {
        return Ok(None);
    }

    let read_str = |name: &str| -> Result<String, UserObjectError> {
        let value = properties
            .get(name)
            .ok_or_else(|| map_err(zbus::Error::MissingField))?;
        <&str>::try_from(value)
            .map(str::to_owned)
            .map_err(|error| map_err(error.into()))
    };

    Ok(find_user_entry(
        read_str("UserName")?,
        read_str("RealName")?,
        read_str("IconFile")?,
        read_str("Shell")?,
        false,
    ))
}

#[derive(Debug, Error)]
#[error("could not read AccountsService user {path}")]
struct UserObjectError {
    path: String,
    #[source]
    source: Box<zbus::Error>,
}

fn find_user_entry(
    username: String,
    real_name: String,
    icon_file: String,
    shell: String,
    system_account: bool,
) -> Option<UserEntry> {
    if username.is_empty() || system_account || !is_login_shell(&shell) {
        return None;
    }

    let real_trimmed = real_name.trim();
    let display_name = if real_trimmed.is_empty() {
        username.clone()
    } else {
        real_trimmed.to_owned()
    };

    Some(UserEntry {
        username,
        display_name,
        icon_path: icon_file,
    })
}

fn is_login_shell(shell: &str) -> bool {
    let Some(shell_name) = std::path::Path::new(shell)
        .file_name()
        .and_then(|name| name.to_str())
    else {
        return false;
    };
    !matches!(shell_name, "false" | "nologin")
}

#[cfg(test)]
mod tests {
    use super::{UserEntry, find_user_entry, is_login_shell};

    #[test]
    fn filters_system_accounts() {
        assert!(
            find_user_entry(
                "daemon".to_owned(),
                "Daemon".to_owned(),
                String::new(),
                "/usr/sbin/nologin".to_owned(),
                true,
            )
            .is_none()
        );
        assert!(
            find_user_entry(
                "service".to_owned(),
                "Service".to_owned(),
                String::new(),
                "/bin/bash".to_owned(),
                true,
            )
            .is_none()
        );
        assert!(is_login_shell("/bin/bash"));
        assert!(!is_login_shell("/bin/false"));
        assert!(!is_login_shell(""));
        assert!(!is_login_shell("/"));
        assert!(!is_login_shell(".."));
    }

    #[test]
    fn preserves_user_metadata() {
        let user = find_user_entry(
            "alice".to_owned(),
            " Alice Example ".to_owned(),
            "/var/lib/AccountsService/icons/alice".to_owned(),
            "/bin/bash".to_owned(),
            false,
        )
        .unwrap();

        assert_eq!(
            user,
            UserEntry {
                username: "alice".to_owned(),
                display_name: "Alice Example".to_owned(),
                icon_path: "/var/lib/AccountsService/icons/alice".to_owned(),
            }
        );
    }
}
