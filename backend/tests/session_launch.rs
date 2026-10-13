//! Exercise the real executable and native shells, without PAM or a desktop.

use std::{
    fs,
    os::unix::{fs::PermissionsExt, process::ExitStatusExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

use serde_json::Value;

struct SessionFixture {
    root: PathBuf,
    backend: PathBuf,
    probe: PathBuf,
    report: PathBuf,
}

impl SessionFixture {
    fn create() -> Self {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root =
            std::env::temp_dir().join(format!("akari-session-{}-{nonce}", std::process::id()));
        fs::create_dir(&root).unwrap();
        let backend = root.join("后端 ' \\ $(false)");
        std::os::unix::fs::symlink(env!("CARGO_BIN_EXE_backend"), &backend).unwrap();
        let probe = root.join("桌面 ' $(false).py");
        fs::write(
            &probe,
            r#"#!/usr/bin/python3
import json, os, sys
with open(sys.argv[1], 'w') as report:
    json.dump({'pid': os.getpid(), 'argv': sys.argv[2:],
               'environment': {key: os.environ.get(key) for key in
                 ['SESSION_LOGIN', 'SESSION_INTERACTIVE', 'SESSION_PROFILE_COUNT',
                  'LANG', 'LC_CTYPE', 'LC_ALL', 'PATH', 'AKARI_TEST_SECRET',
                  'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE']}}, report)
print('desktop stdout')
print('desktop stderr', file=sys.stderr)
"#,
        )
        .unwrap();
        fs::set_permissions(&probe, fs::Permissions::from_mode(0o700)).unwrap();
        let report = root.join("report.json");
        Self {
            root,
            backend,
            probe,
            report,
        }
    }

    fn get_command(&self, shell: &str, login: bool, arguments: &[&str]) -> Command {
        let mut command = if login {
            let mut command = Command::new(shell);
            command.args([
                "-l",
                "-c",
                "exec \"$AKARI_SESSION_EXECUTABLE\" --exec-desktop",
            ]);
            command
        } else {
            let mut command = Command::new(env!("CARGO_BIN_EXE_backend"));
            command.arg("--exec-desktop");
            command
        };
        let mut desktop = vec![self.probe.to_str().unwrap(), self.report.to_str().unwrap()];
        desktop.extend(arguments);
        command
            .env_clear()
            .env("HOME", &self.root)
            .env("SHELL", shell)
            .env("PATH", "/usr/bin:/bin")
            .env("XDG_CONFIG_HOME", self.root.join(".config"))
            .env("XDG_STATE_HOME", self.root.join("state"))
            .env("AKARI_TEST_SECRET", "greeter-internal")
            .env("AKARI_SESSION_EXECUTABLE", &self.backend)
            .env(
                "AKARI_SESSION_INVOCATION",
                serde_json::json!({
                    "session_id": "wayland:test", "source": "test.desktop", "command": desktop
                })
                .to_string(),
            )
            .env("PYTHONCOERCECLOCALE", "0")
            .env("PYTHONUTF8", "1")
            .env("XDG_CURRENT_DESKTOP", "Hyprland")
            .env("XDG_SESSION_TYPE", "wayland");
        command
    }

    fn get_report(&self) -> Value {
        serde_json::from_slice(&fs::read(&self.report).unwrap()).unwrap()
    }

    fn get_logs(&self, state: &str) -> Vec<PathBuf> {
        fs::read_dir(self.root.join(state).join("akari/sessions"))
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .collect()
    }
}

impl Drop for SessionFixture {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.root).unwrap();
    }
}

#[test]
fn native_login_shells_preserve_environment_arguments_and_process_identity() {
    let mut tested = Vec::new();
    for shell in ["/bin/bash", "/bin/sh", "/usr/bin/zsh", "/usr/bin/fish"] {
        if !Path::new(shell).is_file() {
            eprintln!("Native-shell integration not run: {shell} is not installed");
            continue;
        }
        tested.push(shell);
        let fixture = SessionFixture::create();
        let exports = "export SESSION_LOGIN='native login'\nexport LC_CTYPE=C.UTF-8\nexport PATH=\"$HOME/native-bin:$PATH\"\nexport XDG_STATE_HOME=\"$HOME/native-state\"\n";
        fs::write(
            fixture.root.join(".profile"),
            format!(
                "export SESSION_PROFILE_COUNT=$(( ${{SESSION_PROFILE_COUNT:-0}} + 1 ))\n{exports}"
            ),
        )
        .unwrap();
        fs::write(fixture.root.join(".bash_profile"), ". \"$HOME/.profile\"\n").unwrap();
        fs::write(
            fixture.root.join(".bashrc"),
            "export SESSION_INTERACTIVE=yes\n",
        )
        .unwrap();
        let zdotdir = fixture.root.join("zsh-config");
        fs::create_dir(&zdotdir).unwrap();
        fs::write(zdotdir.join(".zprofile"), exports).unwrap();
        fs::write(zdotdir.join(".zshrc"), "export SESSION_INTERACTIVE=yes\n").unwrap();
        let fish = fixture.root.join(".config/fish");
        fs::create_dir_all(&fish).unwrap();
        fs::write(fish.join("config.fish"), "if status is-login\n set -gx SESSION_LOGIN 'native login'\n set -gx LC_CTYPE C.UTF-8\n set -gx PATH $HOME/native-bin $PATH\n set -gx XDG_STATE_HOME $HOME/native-state\nend\nif status is-interactive\n set -gx SESSION_INTERACTIVE yes\nend\n").unwrap();

        let arguments = [
            "",
            "中文 路径",
            "it's quoted",
            "$HOME `false` $(false); exit 99",
            "literal \\ backslash",
            "line\nbreak",
        ];
        let child = fixture
            .get_command(shell, true, &arguments)
            .env("ZDOTDIR", &zdotdir)
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        let pid = child.id();
        let output = child.wait_with_output().unwrap();
        assert!(
            output.status.success(),
            "shell={shell} status={:?}",
            output.status
        );
        assert!(
            output.stderr.is_empty(),
            "shell={shell} stderr={:?}",
            output.stderr
        );
        let report = fixture.get_report();
        assert_eq!(report["pid"], pid, "shell={shell}");
        assert_eq!(
            report["argv"],
            serde_json::json!(arguments),
            "shell={shell}"
        );
        let environment = &report["environment"];
        assert_eq!(
            environment["SESSION_LOGIN"], "native login",
            "shell={shell}"
        );
        assert!(
            environment["SESSION_INTERACTIVE"].is_null(),
            "shell={shell}"
        );
        assert_eq!(environment["LC_CTYPE"], "C.UTF-8");
        assert!(
            environment["PATH"]
                .as_str()
                .unwrap()
                .starts_with(&format!("{}/native-bin:", fixture.root.display()))
        );
        assert!(environment["AKARI_TEST_SECRET"].is_null());
        assert_eq!(environment["XDG_CURRENT_DESKTOP"], "Hyprland");
        assert_eq!(environment["XDG_SESSION_TYPE"], "wayland");
        if shell == "/bin/bash" || shell == "/bin/sh" {
            assert_eq!(environment["SESSION_PROFILE_COUNT"], "1", "shell={shell}");
        }
        assert!(!fixture.root.join("state").exists());
        let logs = fixture.get_logs("native-state");
        assert_eq!(logs.len(), 1);
        assert_eq!(
            fs::metadata(&logs[0]).unwrap().permissions().mode() & 0o777,
            0o600
        );
        let log = fs::read_to_string(&logs[0]).unwrap();
        assert!(log.contains("activation_owner=desktop"));
        assert!(log.contains("desktop stdout"));
        assert!(log.contains("desktop stderr"));
        assert!(!log.contains("greeter-internal"));
    }
    assert!(tested.contains(&"/bin/sh"));
}

#[test]
fn locale_fallback_preserves_explicit_overrides_and_diagnoses_invalid_locales() {
    for (language, ctype, all, expected) in [
        (None, None, None, "C.UTF-8"),
        (Some(""), None, None, "C.UTF-8"),
        (Some("C"), Some("C.UTF-8"), None, "C"),
        (Some("C.UTF-8"), None, Some("C"), "C.UTF-8"),
        (
            Some("akari_invalid_locale"),
            None,
            None,
            "akari_invalid_locale",
        ),
    ] {
        let fixture = SessionFixture::create();
        let mut command = fixture.get_command("/bin/sh", false, &[]);
        for (name, value) in [("LANG", language), ("LC_CTYPE", ctype), ("LC_ALL", all)] {
            if let Some(value) = value {
                command.env(name, value);
            }
        }
        let output = command.output().unwrap();
        assert!(output.status.success());
        let environment = &fixture.get_report()["environment"];
        assert_eq!(environment["LANG"], expected);
        assert_eq!(environment["LC_CTYPE"], serde_json::json!(ctype));
        assert_eq!(environment["LC_ALL"], serde_json::json!(all));
        if language == Some("akari_invalid_locale") {
            let log = fs::read_to_string(&fixture.get_logs("state")[0]).unwrap();
            assert!(log.contains("Cannot set"), "{log}");
        }
    }
}

#[test]
fn desktop_exit_and_signals_are_preserved() {
    for (script, code, signal) in [
        ("exit 23", Some(23), None),
        ("kill -TERM $$", None, Some(15)),
    ] {
        let fixture = SessionFixture::create();
        let status = fixture
            .get_command("/bin/sh", true, &[])
            .env(
                "AKARI_SESSION_INVOCATION",
                serde_json::json!({
                    "session_id": "wayland:test", "source": "test.desktop",
                    "command": ["/bin/sh", "-c", script]
                })
                .to_string(),
            )
            .status()
            .unwrap();
        assert_eq!(status.code(), code);
        assert_eq!(status.signal(), signal);
    }
}

#[test]
fn malformed_invocation_and_failed_desktop_exec_have_actionable_diagnostics() {
    let fixture = SessionFixture::create();
    let output = fixture
        .get_command("/bin/sh", false, &[])
        .env("AKARI_SESSION_INVOCATION", "invalid json")
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("expected value"));
    fs::remove_file(&fixture.probe).unwrap();
    let output = fixture.get_command("/bin/sh", true, &[]).output().unwrap();
    assert!(!output.status.success());
    let log = fs::read_to_string(&fixture.get_logs("state")[0]).unwrap();
    assert!(log.contains("desktop_exec_failed"));
}
