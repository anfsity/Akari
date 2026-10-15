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
        let mut command = Command::new(env!("CARGO_BIN_EXE_backend"));
        command.arg(if login {
            "--start-session"
        } else {
            "--exec-desktop"
        });
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
            .env("AKARI_SPLASH_BIN", self.root.join("akari-splash"))
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

    fn get_logs(&self, state: &str, stage: &str) -> Vec<PathBuf> {
        fs::read_dir(self.root.join(state).join("akari/sessions"))
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .filter(|path| {
                path.file_name()
                    .unwrap()
                    .to_str()
                    .unwrap()
                    .starts_with(stage)
            })
            .collect()
    }
}

impl Drop for SessionFixture {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.root).unwrap();
    }
}

#[test]
fn desktop_waits_for_splash_exit_and_renderer_failures_remain_optional() {
    for status in [0, 1] {
        let fixture = SessionFixture::create();
        let splash = fixture.root.join("akari-splash");
        fs::write(
            &splash,
            format!(
                r#"#!/usr/bin/python3
import os, pathlib, sys, time
root = pathlib.Path(os.environ['HOME'])
assert sys.argv[1:] == ['kms']
assert os.environ['AKARI_SPLASH_DURATION'] == '3'
assert int(os.environ['AKARI_SPLASH_PARENT_PID']) == os.getppid()
(root / 'splash.pid').write_text(str(os.getpid()))
time.sleep(0.05)
(root / 'released').touch()
print('splash stdout')
print('splash stderr', file=sys.stderr)
sys.exit({status})
"#
            ),
        )
        .unwrap();
        fs::set_permissions(&splash, fs::Permissions::from_mode(0o700)).unwrap();
        let probe = fs::read_to_string(&fixture.probe).unwrap();
        fs::write(
            &fixture.probe,
            probe.replace(
                "import json, os, sys",
                r#"import json, os, sys, pathlib
root = pathlib.Path(sys.argv[1]).parent
assert (root / 'released').exists()
try: os.kill(int((root / 'splash.pid').read_text()), 0)
except ProcessLookupError: pass
else: raise AssertionError('desktop started before splash exit')"#,
            ),
        )
        .unwrap();
        let output = fixture
            .get_command("/bin/sh", false, &[])
            .env("AKARI_SPLASH_DURATION", "3")
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(output.stdout.is_empty());
        assert!(output.stderr.is_empty());
        fixture.get_report();
        let log = fs::read_to_string(&fixture.get_logs("state", "session-")[0]).unwrap();
        assert!(log.contains("splash stdout"));
        assert!(log.contains("splash stderr"));
        assert!(log.contains("event=splash_finished"));
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
        let exports = "printf 'native stdout\\n'\nprintf 'native stderr\\n' >&2\nexport SESSION_LOGIN='native login'\nexport LC_CTYPE=C.UTF-8\nexport PATH=\"$HOME/native-bin:$PATH\"\nexport XDG_STATE_HOME=\"$HOME/native-state\"\n";
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
        fs::write(fish.join("config.fish"), "printf 'native stdout\\n'\nprintf 'native stderr\\n' >&2\nif status is-login\n set -gx SESSION_LOGIN 'native login'\n set -gx LC_CTYPE C.UTF-8\n set -gx PATH $HOME/native-bin $PATH\n set -gx XDG_STATE_HOME $HOME/native-state\nend\nif status is-interactive\n set -gx SESSION_INTERACTIVE yes\nend\n").unwrap();

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
            .stdout(Stdio::piped())
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
            output.stdout.is_empty(),
            "shell={shell} stdout={:?}",
            output.stdout
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
        let startup_logs = fixture.get_logs("state", "startup-");
        assert_eq!(startup_logs.len(), 1);
        assert_eq!(
            fs::metadata(&startup_logs[0]).unwrap().permissions().mode() & 0o777,
            0o600
        );
        let startup = fs::read_to_string(&startup_logs[0]).unwrap();
        assert!(
            startup.contains("native stdout"),
            "shell={shell} log={startup}"
        );
        assert!(
            startup.contains("native stderr"),
            "shell={shell} log={startup}"
        );
        let logs = fixture.get_logs("native-state", "session-");
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
            let log = fs::read_to_string(&fixture.get_logs("state", "session-")[0]).unwrap();
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
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
    let log = fs::read_to_string(&fixture.get_logs("state", "session-")[0]).unwrap();
    assert!(log.contains("desktop_exec_failed"));
}

#[test]
fn native_shell_failures_stay_in_private_startup_logs() {
    let fixture = SessionFixture::create();
    let shell = fixture.root.join("failed-shell");
    fs::write(
        &shell,
        "#!/bin/sh\nprintf 'shell startup failed\\n' >&2\nexit 23\n",
    )
    .unwrap();
    fs::set_permissions(&shell, fs::Permissions::from_mode(0o700)).unwrap();
    let output = fixture
        .get_command(shell.to_str().unwrap(), true, &[])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(23));
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
    let logs = fixture.get_logs("state", "startup-");
    assert_eq!(logs.len(), 1);
    assert!(
        fs::read_to_string(&logs[0])
            .unwrap()
            .contains("shell startup failed")
    );
    assert!(fixture.get_logs("state", "session-").is_empty());

    fs::remove_file(&shell).unwrap();
    let output = fixture
        .get_command(shell.to_str().unwrap(), true, &[])
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
    assert!(fixture.get_logs("state", "startup-").iter().any(|path| {
        fs::read_to_string(path)
            .unwrap()
            .contains("native_shell_exec_failed")
    }));
}
