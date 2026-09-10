//! User discovery through the system AccountsService D-Bus API.

use std::sync::Arc;

use thiserror::Error;
use tokio::sync::OnceCell;
use zbus::{proxy, proxy::CacheProperties, zvariant::OwnedObjectPath};

#[proxy(
    default_service = "org.freedesktop.Accounts",
    default_path = "/org/freedesktop/Accounts",
    interface = "org.freedesktop.Accounts"
)]
trait AccountsService {
    fn list_cached_users(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
}

#[proxy(
    default_service = "org.freedesktop.Accounts",
    interface = "org.freedesktop.Accounts.User"
)]
trait AccountsServiceUser {
    #[zbus(property)]
    fn user_name(&self) -> zbus::Result<String>;

    #[zbus(property)]
    fn real_name(&self) -> zbus::Result<String>;

    #[zbus(property)]
    fn icon_file(&self) -> zbus::Result<String>;

    #[zbus(property)]
    fn shell(&self) -> zbus::Result<String>;

    #[zbus(property)]
    fn system_account(&self) -> zbus::Result<bool>;
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

/// Reads login users from AccountsService without parsing NSS or passwd files.
///
/// The system-bus connection is initialized lazily and shared by cloned
/// catalogs. User properties are fetched asynchronously by zbus.
#[derive(Clone, Debug, Default)]
pub struct UserCatalog {
    connection: Arc<OnceCell<zbus::Connection>>,
}

impl UserCatalog {
    pub async fn list(&self) -> Result<Vec<UserEntry>, UserCatalogError> {
        let connection = self.system_connection().await?;
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
                    tracing::debug!(%error, "skipping unavailable AccountsService user");
                }
            }
        }
        users.sort_by(|left, right| left.username.cmp(&right.username));
        Ok(users)
    }

    async fn system_connection(&self) -> Result<zbus::Connection, UserCatalogError> {
        let connection = self
            .connection
            .get_or_try_init(|| async {
                zbus::Connection::system()
                    .await
                    .map_err(UserCatalogError::Connect)
            })
            .await?;
        Ok(connection.clone())
    }
}

async fn read_user(
    connection: &zbus::Connection,
    path: &OwnedObjectPath,
) -> Result<Option<UserEntry>, UserObjectError> {
    let map_err = |source| UserObjectError {
        path: path.to_string(),
        source,
    };

    let proxy = AccountsServiceUserProxy::builder(connection)
        .path(path.as_str())
        .map_err(map_err)?
        .cache_properties(CacheProperties::Yes)
        .build()
        .await
        .map_err(map_err)?;

    let username = proxy.user_name().await.map_err(map_err)?;
    let real_name = proxy.real_name().await.map_err(map_err)?;
    let icon_file = proxy.icon_file().await.map_err(map_err)?;
    let shell = proxy.shell().await.map_err(map_err)?;
    let system_account = proxy.system_account().await.map_err(map_err)?;

    Ok(make_user_entry(
        username,
        real_name,
        icon_file,
        shell,
        system_account,
    ))
}

#[derive(Debug, Error)]
#[error("could not read AccountsService user {path}")]
struct UserObjectError {
    path: String,
    #[source]
    source: zbus::Error,
}

fn make_user_entry(
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
    if shell.is_empty() {
        return false;
    }
    let shell_name = std::path::Path::new(shell)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or_default();
    !matches!(shell_name, "false" | "nologin")
}

#[cfg(test)]
mod tests {
    use super::{UserEntry, is_login_shell, make_user_entry};

    #[test]
    fn filters_non_login_and_system_accounts() {
        assert!(
            make_user_entry(
                "daemon".to_owned(),
                "Daemon".to_owned(),
                String::new(),
                "/usr/sbin/nologin".to_owned(),
                true,
            )
            .is_none()
        );
        assert!(
            make_user_entry(
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
    }

    #[test]
    fn preserves_accounts_service_metadata() {
        let user = make_user_entry(
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
