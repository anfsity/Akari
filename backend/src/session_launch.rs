//! User-side session handoff, separate from the greeter's bus and runtime.
//!
//! greetd forwards execution to the account's login shell. The fixed shell
//! expression only expands one executable path; the desktop argv travels as
//! JSON in the environment, avoiding interpreter-specific argument escaping.
//! Existing desktop managers own readiness and activation-environment cleanup.

use std::{
    env,
    ffi::OsString,
    fs::{DirBuilder, File, OpenOptions},
    io::{self, Write},
    os::unix::{
        fs::{DirBuilderExt, OpenOptionsExt},
        process::CommandExt,
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

use crate::session_catalog::SessionEntry;
use crate::terminal_transition::start_transition_animation;
use serde::{Deserialize, Serialize};

pub const EXEC_DESKTOP: &str = "--exec-desktop";

#[derive(Deserialize, Serialize)]
struct SessionInvocation {
    session_id: String,
    source: PathBuf,
    command: Vec<String>,
}

pub fn get_session_launch(session: &SessionEntry) -> io::Result<(Vec<String>, Vec<String>)> {
    let executable = env::current_exe()?
        .into_os_string()
        .into_string()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "backend path is not UTF-8"))?;
    let invocation = serde_json::to_string(&SessionInvocation {
        session_id: session.session_id.clone(),
        source: session.source.clone(),
        command: session.exec.clone(),
    })
    .map_err(io::Error::other)?;
    let command = ["/bin/sh", "-c",
        ": \"${SHELL:?PAM did not supply SHELL}\"; exec \"$SHELL\" -l -c 'exec \"$AKARI_SESSION_EXECUTABLE\" --exec-desktop'"]
        .map(str::to_owned).to_vec();
    let mut environment = vec![
        "PATH=/usr/local/bin:/usr/bin:/bin".to_owned(),
        format!("XDG_SESSION_TYPE={}", session.session_type.as_str()),
    ];
    if let Some(desktop_name) = session.desktop_names.first() {
        environment.push(format!("XDG_SESSION_DESKTOP={desktop_name}"));
        environment.push(format!(
            "XDG_CURRENT_DESKTOP={}",
            session.desktop_names.join(":")
        ));
    }
    environment.push(format!("AKARI_SESSION_EXECUTABLE={executable}"));
    environment.push(format!("AKARI_SESSION_INVOCATION={invocation}"));
    Ok((command, environment))
}

pub fn exec_desktop() -> io::Result<()> {
    let invocation = env::var("AKARI_SESSION_INVOCATION").map_err(io::Error::other)?;
    let invocation: SessionInvocation =
        serde_json::from_str(&invocation).map_err(io::Error::other)?;
    if invocation.command.is_empty() || invocation.command[0].is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "desktop command is empty",
        ));
    }
    let mut log = create_session_log()?;
    let mut command = Command::new(&invocation.command[0]);
    command.args(&invocation.command[1..]);

    // Native configuration owns explicit locale choices. A missing LANG gets
    // a UTF-8 baseline; LC_ALL and category-specific overrides stay intact.
    let language = env::var_os("LANG")
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| OsString::from("C.UTF-8"));
    command.env("LANG", &language);
    for (name, _) in env::vars_os() {
        if name.to_string_lossy().starts_with("AKARI_") {
            command.env_remove(name);
        }
    }
    writeln!(
        log,
        "event=user_session_initialized session={:?} source={:?} shell={:?} activation_owner=desktop",
        invocation.session_id,
        invocation.source,
        env::var_os("SHELL")
    )?;
    writeln!(
        log,
        "LANG={language:?} LC_ALL={:?} LC_CTYPE={:?}",
        env::var_os("LC_ALL"),
        env::var_os("LC_CTYPE")
    )?;
    match Command::new("/usr/bin/locale")
        .arg("charmap")
        .env("LANG", &language)
        .output()
    {
        Ok(output) => {
            writeln!(
                log,
                "event=locale_checked status={} charmap={:?} diagnostic={:?}",
                output.status,
                String::from_utf8_lossy(&output.stdout).trim(),
                String::from_utf8_lossy(&output.stderr).trim()
            )?;
        }
        Err(error) => writeln!(log, "event=locale_check_failed error={error:?}")?,
    }
    command
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log.try_clone()?));
    // Display preparation is optional; a missing console or failed renderer
    // must not prevent an otherwise valid desktop session from starting.
    if let Err(error) = start_transition_animation(&log) {
        writeln!(log, "event=transition_animation_failed error={error:?}")?;
    }
    let error = command.exec();
    writeln!(
        log,
        "event=desktop_exec_failed executable={:?} error={error:?}",
        invocation.command[0]
    )?;
    Err(error)
}

fn create_session_log() -> io::Result<File> {
    let state = match env::var_os("XDG_STATE_HOME").filter(|value| Path::new(value).is_absolute()) {
        Some(path) => PathBuf::from(path),
        None => PathBuf::from(env::var_os("HOME").ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidInput, "PAM did not supply HOME")
        })?)
        .join(".local/state"),
    };
    let directory = state.join("akari/sessions");
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&directory)?;
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(io::Error::other)?
        .as_nanos();
    let path = directory.join(format!("session-{timestamp}-{}.log", std::process::id()));
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&path)
}
