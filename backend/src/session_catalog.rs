use std::{
    env, fs, io,
    path::{Path, PathBuf},
};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum SessionCatalogError {
    #[error("could not read session directory")]
    ReadDirectory(#[source] io::Error),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SessionEntry {
    pub session_id: String,
    pub session_type: SessionType,
    pub name: String,
    pub exec: Vec<String>,
    pub desktop_names: Vec<String>,
    pub source: PathBuf,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionType {
    Wayland,
    X11,
}

impl SessionType {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Wayland => "wayland",
            Self::X11 => "x11",
        }
    }
}

#[derive(Clone, Debug)]
pub struct SessionCatalog {
    roots: Vec<(SessionType, PathBuf)>,
}

impl Default for SessionCatalog {
    fn default() -> Self {
        let wayland_root = env::var_os("MOZAIS_WAYLAND_SESSIONS")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/usr/share/wayland-sessions"));
        let x11_root = env::var_os("MOZAIS_X11_SESSIONS")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/usr/share/xsessions"));

        Self::from_roots(wayland_root, x11_root)
    }
}

impl SessionCatalog {
    pub fn from_roots(wayland_root: PathBuf, x11_root: PathBuf) -> Self {
        Self {
            roots: vec![
                (SessionType::Wayland, wayland_root),
                (SessionType::X11, x11_root),
            ],
        }
    }

    pub fn list(&self) -> Result<Vec<SessionEntry>, SessionCatalogError> {
        let mut sessions = Vec::new();

        for (session_type, root) in &self.roots {
            let entries = match fs::read_dir(root) {
                Ok(entries) => entries,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(SessionCatalogError::ReadDirectory(error)),
            };

            for entry in entries {
                let entry = match entry {
                    Ok(entry) => entry,
                    Err(_) => continue,
                };
                let path = entry.path();
                if path.extension().and_then(|extension| extension.to_str()) != Some("desktop") {
                    continue;
                }

                if let Some(session) = parse_session_file(&path, *session_type)
                    && session_available(&session)
                {
                    sessions.push(session);
                }
            }
        }

        sessions.sort_by(|left, right| left.session_id.cmp(&right.session_id));
        Ok(sessions)
    }

    pub fn find(&self, session_id: &str) -> Result<Option<SessionEntry>, SessionCatalogError> {
        Ok(self
            .list()?
            .into_iter()
            .find(|session| session.session_id == session_id))
    }
}

fn parse_session_file(path: &Path, session_type: SessionType) -> Option<SessionEntry> {
    let contents = fs::read_to_string(path).ok()?;
    let fields = parse_desktop_entry(&contents);

    if fields.get("Type").map(String::as_str) != Some("Application")
        || is_true(fields.get("Hidden"))
        || is_true(fields.get("NoDisplay"))
    {
        return None;
    }

    let name = fields.get("Name")?.to_owned();
    let exec = tokenize_exec(fields.get("Exec")?).ok()?;
    if exec.is_empty() || exec.iter().any(|token| token.contains('%')) {
        return None;
    }
    if fields
        .get("TryExec")
        .is_some_and(|command| !command_available(command))
    {
        return None;
    }

    let stem = path.file_stem()?.to_str()?;
    if stem.is_empty() {
        return None;
    }

    let desktop_names = fields
        .get("DesktopNames")
        .map(|value| {
            value
                .split(';')
                .map(str::trim)
                .filter(|name| !name.is_empty() && is_safe_env_value(name))
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default();

    Some(SessionEntry {
        session_id: format!("{}:{stem}", session_type.as_str()),
        session_type,
        name,
        exec,
        desktop_names,
        source: path.to_path_buf(),
    })
}

fn parse_desktop_entry(contents: &str) -> std::collections::BTreeMap<String, String> {
    let mut fields = std::collections::BTreeMap::new();
    let mut in_desktop_entry = false;

    for raw_line in contents.lines() {
        let line = raw_line.trim();
        if line.starts_with('[') && line.ends_with(']') {
            in_desktop_entry = line == "[Desktop Entry]";
            continue;
        }
        if !in_desktop_entry || line.is_empty() || line.starts_with('#') {
            continue;
        }

        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        if key.contains('[') {
            continue;
        }
        fields.insert(key.to_owned(), unescape_desktop_value(value));
    }

    fields
}

fn unescape_desktop_value(value: &str) -> String {
    let mut result = String::with_capacity(value.len());
    let mut escaped = false;

    for character in value.chars() {
        if escaped {
            result.push(match character {
                's' => ' ',
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '\\' => '\\',
                other => other,
            });
            escaped = false;
        } else if character == '\\' {
            escaped = true;
        } else {
            result.push(character);
        }
    }

    if escaped {
        result.push('\\');
    }
    result
}

fn tokenize_exec(value: &str) -> Result<Vec<String>, ()> {
    let mut tokens = Vec::new();
    let mut token = String::new();
    let mut quote = None;
    let mut escaped = false;

    for character in value.chars() {
        if escaped {
            token.push(character);
            escaped = false;
            continue;
        }

        match quote {
            Some(current_quote) if character == current_quote => quote = None,
            Some(_) if character == '\\' => escaped = true,
            Some(_) => token.push(character),
            None if character == '\\' => escaped = true,
            None if character == '\'' || character == '"' => quote = Some(character),
            None if character.is_whitespace() => {
                if !token.is_empty() {
                    tokens.push(std::mem::take(&mut token));
                }
            }
            None => token.push(character),
        }
    }

    if escaped || quote.is_some() {
        return Err(());
    }
    if !token.is_empty() {
        tokens.push(token);
    }

    Ok(tokens)
}

fn session_available(session: &SessionEntry) -> bool {
    let Some(command) = session.exec.first() else {
        return false;
    };
    command_available(command)
}

fn command_available(command: &str) -> bool {
    if command.is_empty()
        || command.contains('\0')
        || (command.contains('/') && !Path::new(command).is_absolute())
    {
        return false;
    }

    if command.contains('/') {
        return is_executable(Path::new(command));
    }

    let path = env::var_os("PATH").unwrap_or_else(|| "/usr/local/bin:/usr/bin:/bin".into());
    env::split_paths(&path).any(|directory| is_executable(&directory.join(command)))
}

fn is_executable(path: &Path) -> bool {
    let Ok(metadata) = fs::metadata(path) else {
        return false;
    };
    if !metadata.is_file() {
        return false;
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        metadata.permissions().mode() & 0o111 != 0
    }

    #[cfg(not(unix))]
    {
        true
    }
}

fn is_true(value: Option<&String>) -> bool {
    value.is_some_and(|value| value.eq_ignore_ascii_case("true"))
}

fn is_safe_env_value(value: &str) -> bool {
    !value.is_empty()
        && !value.contains('\0')
        && !value.contains('\n')
        && !value.contains('\r')
        && !value.contains('=')
}

#[cfg(test)]
mod tests {
    use std::{
        fs,
        path::PathBuf,
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::{SessionCatalog, SessionType, tokenize_exec};

    fn test_root() -> PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock before epoch")
            .as_nanos();
        let root = std::env::temp_dir().join(format!("mozais-sessions-{suffix}"));
        fs::create_dir_all(&root).unwrap();
        root
    }

    #[test]
    fn parses_and_filters_session_desktop_entries() {
        let root = test_root();
        fs::write(
            root.join("sway.desktop"),
            "[Desktop Entry]\nType=Application\nName=Sway\nExec=sh -c 'exec sway'\nDesktopNames=sway;wlroots\n",
        )
        .unwrap();
        fs::write(
            root.join("hidden.desktop"),
            "[Desktop Entry]\nType=Application\nName=Hidden\nExec=definitely-not-installed\nHidden=true\n",
        )
        .unwrap();

        let catalog = SessionCatalog::from_roots(root.clone(), PathBuf::from("/does/not/exist"));
        let sessions = catalog.list().unwrap();

        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].session_id, "wayland:sway");
        assert_eq!(sessions[0].session_type, SessionType::Wayland);
        assert_eq!(sessions[0].desktop_names, ["sway", "wlroots"]);
        assert_eq!(sessions[0].exec, ["sh", "-c", "exec sway"]);

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn rejects_unclosed_quotes_and_preserves_quoted_arguments() {
        assert_eq!(
            tokenize_exec("uwsm start -e -D Hyprland hyprland.desktop")
                .unwrap()
                .len(),
            6
        );
        assert_eq!(
            tokenize_exec("wrapper 'argument with spaces'").unwrap(),
            ["wrapper", "argument with spaces"]
        );
        assert!(tokenize_exec("wrapper 'unfinished").is_err());
    }
}
