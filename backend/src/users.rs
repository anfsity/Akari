use std::{fs, io};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum UserCatalogError {
    #[error("could not read /etc/passwd")]
    Read(#[source] io::Error),
}

#[derive(Clone, Debug, Default)]
pub struct UserCatalog;

impl UserCatalog {
    pub fn list(&self) -> Result<Vec<(String, String, String)>, UserCatalogError> {
        let contents = fs::read_to_string("/etc/passwd").map_err(UserCatalogError::Read)?;
        let mut users = contents
            .lines()
            .filter_map(parse_passwd_entry)
            .collect::<Vec<_>>();
        users.sort_by(|left, right| left.0.cmp(&right.0));
        Ok(users)
    }
}

fn parse_passwd_entry(line: &str) -> Option<(String, String, String)> {
    if line.is_empty() || line.starts_with('#') {
        return None;
    }

    let fields = line.split(':').collect::<Vec<_>>();
    if fields.len() < 7 {
        return None;
    }

    let username = fields[0];
    if username.is_empty() || fields[6].is_empty() {
        return None;
    }
    let shell_name = std::path::Path::new(fields[6])
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or_default();
    if matches!(shell_name, "false" | "nologin") {
        return None;
    }

    let uid = fields[2].parse::<u32>().ok()?;
    if uid < 1000 && uid != 0 {
        return None;
    }

    let display_name = fields[4]
        .split(',')
        .next()
        .unwrap_or_default()
        .trim()
        .to_owned();
    let icon_path = format!("/var/lib/AccountsService/icons/{username}");
    let icon_path = if std::path::Path::new(&icon_path).is_file() {
        icon_path
    } else {
        String::new()
    };

    Some((username.to_owned(), display_name, icon_path))
}

#[cfg(test)]
mod tests {
    use super::parse_passwd_entry;

    #[test]
    fn filters_system_and_nologin_users() {
        assert!(parse_passwd_entry("daemon:x:1:1:Daemon:/usr/sbin:/usr/sbin/nologin").is_none());
        assert!(
            parse_passwd_entry("greeter:x:1001:1001:Greeter:/home/greeter:/bin/bash").is_some()
        );
    }

    #[test]
    fn extracts_display_name_before_gecos_commas() {
        let user =
            parse_passwd_entry("alice:x:1000:1000:Alice Example,,:/home/alice:/bin/bash").unwrap();
        assert_eq!(user.0, "alice");
        assert_eq!(user.1, "Alice Example");
        assert_eq!(user.2, "");
    }
}
