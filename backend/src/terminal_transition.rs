//! One embedded renderer shared by greeter preparation and user handoff.
//! Python is already a login runtime dependency. Embedding the source keeps
//! upgrades and rollback tied to the executable that launches the session.

use std::{
    fs::File,
    io,
    process::{Command, Stdio},
};

pub const PREPARE_TRANSITION: &str = "--prepare-transition";
const RENDERER: &str = include_str!("../../scripts/ascii-transition.py");

pub fn prepare_transition() -> io::Result<()> {
    let status = Command::new("python3")
        .args(["-c", RENDERER, "prepare"])
        .status()?;
    if !status.success() {
        return Err(io::Error::other(format!(
            "ASCII preparation exited with {status}"
        )));
    }
    Ok(())
}

pub fn start_transition_animation(log: &File) -> io::Result<()> {
    let status = Command::new("python3")
        .args([
            "-c",
            RENDERER,
            "animate",
            "--owner",
            &std::process::id().to_string(),
        ])
        .stdin(Stdio::null())
        .stdout(log.try_clone()?)
        .stderr(log.try_clone()?)
        .status()?;
    if !status.success() {
        return Err(io::Error::other(format!(
            "ASCII animator exited with {status}"
        )));
    }
    Ok(())
}
