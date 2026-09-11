//! Discovery and validation of login sessions advertised by desktop files.
//!
//! The catalog reads Wayland and X11 session directories, parses only the
//! `[Desktop Entry]` group, and keeps the launch command private to the
//! backend. The D-Bus API exposes a stable session ID and display metadata;
//! callers never submit an arbitrary `Exec` command.

use std::{
    env, fs, io,
    path::{Path, PathBuf},
};

use thiserror::Error;

const SESSION_COMMAND_PATH: &str = "/usr/local/bin:/usr/bin:/bin";

/// Errors encountered while reading a configured session directory.
#[derive(Debug, Error)]
pub enum SessionCatalogError {
    #[error("could not read session directory")]
    ReadDirectory(#[source] io::Error),
}

/// A validated desktop-session candidate and the command used to launch it.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SessionEntry {
    /// Stable backend-owned identifier, such as `wayland:sway`.
    pub session_id: String,
    /// Whether the entry came from the Wayland or X11 catalog.
    pub session_type: SessionType,
    /// User-facing `Name=` value from the desktop entry.
    pub name: String,
    /// Tokenized, backend-owned `Exec=` command passed to greetd.
    pub exec: Vec<String>,
    /// Sanitized `DesktopNames=` values used to construct session metadata.
    pub desktop_names: Vec<String>,
    /// Source desktop-entry path, retained for backend diagnostics and selection.
    pub source: PathBuf,
}

/// Display-server family advertised by a session desktop entry.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionType {
    /// A Wayland session from the Wayland session directory.
    Wayland,
    /// An X11 session from the X session directory.
    X11,
}

impl SessionType {
    /// Returns the stable lowercase value used in session IDs and environment variables.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Wayland => "wayland",
            Self::X11 => "x11",
        }
    }
}

/// Reads, filters, and resolves available Wayland and X11 session entries.
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
    /// Creates a catalog from explicit roots, primarily for isolated tests and alternate layouts.
    pub fn from_roots(wayland_root: PathBuf, x11_root: PathBuf) -> Self {
        Self {
            roots: vec![
                (SessionType::Wayland, wayland_root),
                (SessionType::X11, x11_root),
            ],
        }
    }

    /// Lists available sessions in deterministic `session_id` order.
    ///
    /// Missing roots are treated as empty catalogs. Unreadable individual
    /// entries and entries whose launch command is unavailable are skipped,
    /// while failures reading an existing directory are returned.
    pub fn list(&self) -> Result<Vec<SessionEntry>, SessionCatalogError> {
        let mut sessions = Vec::new();

        for (session_type, root) in &self.roots {
            let entries = match fs::read_dir(root) {
                Ok(entries) => entries,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(SessionCatalogError::ReadDirectory(error)),
            };

            for entry in entries {
                // One broken desktop file should not hide otherwise usable sessions.
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

    /// Finds one session by its backend-owned ID after refreshing the catalog from disk.
    pub fn find(&self, session_id: &str) -> Result<Option<SessionEntry>, SessionCatalogError> {
        Ok(self
            .list()?
            .into_iter()
            .find(|session| session.session_id == session_id))
    }
}

/// Parses and validates one desktop entry before it can reach the launch path.
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
    let mut exec = tokenize_exec(fields.get("Exec")?).ok()?;
    if exec.is_empty() || exec.iter().any(|token| token.contains('%')) {
        return None;
    }
    exec[0] = resolve_command(&exec[0])?;
    if fields
        .get("TryExec")
        .is_some_and(|command| resolve_command(command).is_none())
    {
        return None;
    }

    let stem = path.file_stem()?.to_str()?;
    if stem.is_empty() {
        return None;
    }

    // DesktopNames is metadata supplied to the launched session, so reject
    // values that could break an environment assignment before storing them.
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

/// Extracts scalar keys from the `[Desktop Entry]` group.
///
/// Group headers, comments, localized keys, malformed assignments, and other
/// groups are ignored. Values use the desktop-entry backslash escapes handled
/// by [`unescape_desktop_value`].
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

/// Decodes the desktop-entry escapes needed by session metadata and commands.
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

/// Tokenizes an `Exec=` value while preserving quoted arguments.
///
/// This implements the small command-line grammar needed for these desktop
/// entries; field-code substitutions are rejected by the caller. Unclosed
/// quotes and trailing escapes return `Err(())`.
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

/// Checks that the executable at the head of a parsed session command exists.
fn session_available(session: &SessionEntry) -> bool {
    session
        .exec
        .first()
        .is_some_and(|command| is_executable(Path::new(command)))
}

/// Resolves a command name through a backend-owned path, or checks an explicit
/// absolute path.
///
/// Empty names, NUL bytes, and relative paths containing `/` are rejected
/// before filesystem inspection. Arguments remain the already-tokenized
/// values from the desktop entry.
fn resolve_command(command: &str) -> Option<String> {
    if command.is_empty()
        || command.contains('\0')
        || (command.contains('/') && !Path::new(command).is_absolute())
    {
        return None;
    }

    if command.contains('/') {
        return is_executable(Path::new(command)).then(|| command.to_owned());
    }

    env::split_paths(SESSION_COMMAND_PATH)
        .map(|directory| directory.join(command))
        .find(|path| is_executable(path))
        .map(|path| path.to_string_lossy().into_owned())
}

/// Returns whether `path` is a regular file with an executable Unix mode bit.
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

/// Accepts environment-safe desktop names that can be serialized as `KEY=value`.
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
        assert_eq!(sessions[0].exec, ["/usr/bin/sh", "-c", "exec sway"]);

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
