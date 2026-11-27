# Security Policy

## Scope & Architecture Boundaries

Akari separates login UI presentation from system authentication:

- **Privilege isolation**: Flutter UI and compiled theme packages run without access to PAM, `greetd` Unix sockets, or root privileges. Authentication and power operations run in `crates/akari-backend` over a private per-session D-Bus interface (`io.akari.Greeter1`).
- **Credential handling**: Authentication responses are wrapped in `zeroize::Zeroizing` in the Rust backend and are never persisted to scene documents, UI slots, or CLI run reports.
- **Deployment boundaries**: Production deployment (`akari install`) runs the greeter under a dedicated unprivileged `akari-greeter` user, stores Akari-owned configuration under `/etc/akari/`, and retains snapshots/backups under `/var/lib/akari/` for safe rollback (`akari login disable` / `akari uninstall`).

## Supported Versions

Akari is currently in pre-1.0 development. Security fixes are applied to the `main` branch.

## Reporting a Vulnerability

Please **do not** report security vulnerabilities—such as authentication bypasses, privilege escalation, PAM stack corruption, or credential leaks—through public GitHub issues.

Instead, report them privately via [GitHub Private Vulnerability Reporting](https://github.com/anfsity/Akari/security/advisories/new).

- When sharing logs (`akari login logs`, `~/.local/state/akari/sessions/`) or system configuration (`/etc/pam.d/greetd`, `/etc/akari/`), review them first and redact any sensitive local environment details.
