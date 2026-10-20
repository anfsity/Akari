# User session environment contract

> [!NOTE]
> **Status**: Login-shell forwarding, `argv` preservation, locale diagnostics, and user session logging are implemented. PAM/VT login and desktop service readiness still require real-login validation.

## 1. Problem & design goals

A desktop launched through Akari must inherit the user's login environment, and services activated by `systemd --user` or D-Bus must receive the required display/session variables before starting.

## 2. Startup order & ownership

```text
greetd / PAM
  -> greetd loads POSIX profiles (/etc/profile, ~/.profile)
  -> User's login shell ($SHELL -l -c) initializes native login config
  -> Akari user-side executor preserves argv, checks locale, and opens user logs
  -> Selected desktop entry starts its desktop/session manager
  -> Session owner publishes activation environment and signals readiness
  -> Dependent user services start (and stop on desktop exit)
```

| Stage | Owner | Completion contract |
| --- | --- | --- |
| **Authentication & PAM** | `greetd` + PAM | Authenticated user context is established |
| **POSIX login baseline** | `greetd` (`source_profile = true`) | `/etc/profile` and `~/.profile` evaluated |
| **Native shell login config** | User's `$SHELL` | Login files (e.g., `.zprofile`, fish login config) evaluated without running interactive `.zshrc` |
| **Desktop command handoff** | Akari user-side executor (`session_launch.rs`) | Internal `AKARI_*` vars stripped, fallback `LANG=C.UTF-8` applied if unset, and desktop `exec`ed with intact `argv` |
| **Activation environment & services** | Desktop / session manager (e.g., UWSM, GNOME, Plasma, or compositor hook) | Display/desktop variables published to `systemd --user` / D-Bus before dependent services start |

> [!IMPORTANT]
> `greetd`'s `start_session` reply only acknowledges handoff from the greeter; it does not mean the desktop compositor or user services are ready.

## 3. Shell & locale rules

- **Shell-agnostic forwarding**: Akari invokes `$SHELL` in non-interactive login mode (`-l -c 'exec "$VARIABLE"'`) without branching on shell names (`bash`, `sh`, `zsh`, and `fish` are covered by integration tests).
- **Safe profile re-evaluation**: Because native login shells may source `/etc/profile` or `~/.profile` again after `greetd`, POSIX profile scripts should remain idempotent.
- **JSON `argv` transport**: Desktop arguments travel as JSON in the `greetd` environment so POSIX and fish shells never re-split or reinterpret desktop arguments.
- **Locale precedence**: Explicit user locale variables are preserved. If `LANG` is unset or empty, the executor supplies `LANG=C.UTF-8` and logs locale diagnostics into `session-*.log`.

## 4. Environment publication boundaries

| Variable group | Publication rule |
| --- | --- |
| **Locale & `PATH`** (`LANG`, `LC_*`, `PATH`) | Initialized by login shell; published by the session owner before service activation |
| **Desktop identity** (`XDG_CURRENT_DESKTOP`, `XDG_SESSION_DESKTOP`, `XDG_SESSION_TYPE`) | Supplied by `.desktop` metadata and finalized by the desktop session manager |
| **Toolkit & input method** (`QT_IM_MODULE`, `XMODIFIERS`, `QT_QPA_PLATFORMTHEME`) | Supplied by user login/desktop config; publish only variables explicitly configured |
| **Display endpoints** (`WAYLAND_DISPLAY`, `DISPLAY`, `XAUTHORITY`) | Published by the compositor / session manager once sockets exist |
| **Transient login / greeter vars** (`XDG_SESSION_ID`, `XDG_VTNR`, `AKARI_*`) | **Never** published globally to `systemd --user` or D-Bus activation environments |

### Session manager integration

- **Managed desktops (GNOME, Plasma, UWSM)**: Retain their native lifecycle (`uwsm finalize`, graphical targets, and teardown). Akari never wraps an already managed entry in a second manager.
- **Direct compositor sessions (e.g., plain Hyprland)**: Rely on the compositor's own activation-environment import (`dbus-update-activation-environment --systemd`). Note that asynchronous startup callbacks in user rice (such as unmodified end-4 Lua scripts) cannot order upstream apps launched before environment publication completes.

## 5. Acceptance checklist

- [ ] Real `greetd` login with `zsh` and `fish` exports login variables without executing interactive-only `.zshrc` blocks.
- [ ] Quoted executable paths, spaces, empty arguments, and `sh -c` survive handoff intact.
- [ ] A compositor child, a newly started `systemd --user` service, and a newly D-Bus-activated service agree on the required variable set.
- [ ] UWSM-managed and direct Hyprland entries behave as expected across login, logout, and config reload.

## References

- [greetd profile configuration](https://man.archlinux.org/man/greetd.5.en)
- [zsh startup files](https://zsh.sourceforge.io/Doc/Release/Files.html) & [fish configuration](https://fishshell.com/docs/current/#configuration)
- [D-Bus activation environment updates](https://dbus.freedesktop.org/doc/dbus-update-activation-environment.1.html)
- [UWSM environment and readiness management](https://github.com/Vladimir-csp/uwsm#readme)
