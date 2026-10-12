# User session environment contract

Status: login-shell forwarding, argv preservation, locale diagnostics, and user
session logging are implemented. PAM/VT login and desktop service readiness
still require real-login validation. Desktop files and user rice are unchanged.

## Problem and existing behavior

A desktop launched through Akari must receive the user's login environment.
Services activated by the user service manager must also receive the relevant
desktop environment before they start. Updating an activation environment does
not update processes that are already running.

The backend resolves a session desktop file and asks greetd to forward execution
to the authenticated account's `$SHELL` in non-interactive login mode. greetd
supplies the PAM environment and POSIX profiles. Native shell configuration is
evaluated by the user's shell, then the backend's user-side executor launches
the selected desktop with intact arguments.

The installed end-4 rice registers its startup callback before `custom/execs.lua`.
Its callback launches applications and environment import commands asynchronously,
including a delayed import. Adding another custom callback does not replace that
callback or order its child processes.

These observations do not establish that only two variables reach systemd:
Hyprland 0.56.2 includes activation-environment imports for display, desktop,
instance, theme, PATH, and data-directory variables. The inspected host configures
the user bus as dbus-broker, whose activation-environment updates are forwarded
to systemd. Actual import success and service startup timing still need runtime
verification.

## Responsibility and startup order

| Responsibility | Owner | Completion condition |
| --- | --- | --- |
| Authentication and login resources | greetd and PAM | Authenticated user session can start |
| POSIX login baseline | greetd profile loading | `/etc/profile` and `~/.profile` evaluated as the authenticated user |
| Native login configuration | User's shell, forwarded by Akari's greetd request | Shell login initialization completed |
| Desktop command handoff and diagnostics | Akari user-side executor | Selected command receives intact arguments and initialized environment |
| Desktop configuration and display endpoints | Selected desktop or compositor | Configuration applied and endpoints available |
| Activation environment, dependent services, and cleanup | Desktop's existing session manager, or explicitly configured compositor integration | Required environment published before dependent services start; teardown belongs to the same owner |

The Akari launcher runs after authentication, as the selected user. The greeter
does not evaluate user shell configuration or publish its own Sway/private-bus
environment to the user's service manager.

```text
greetd / PAM
  -> greetd loads POSIX profiles
  -> user's login shell initializes its native configuration
  -> Akari user-side executor preserves argv, checks locale, and opens user logs
  -> selected desktop entry starts its desktop/session manager
  -> desktop endpoints and configuration are ready
  -> session owner publishes activation environment and confirms readiness
  -> dependent services start
  -> session owner stops those services and cleans up on desktop exit
```

Acceptance of greetd's `start_session` request is a handoff acknowledgment. It
must not be reported as desktop or service readiness.

## Login environment

Initialize the account's configured shell in non-interactive login mode. Let
the shell find its own startup files, including zsh's `ZDOTDIR` and fish's XDG
configuration paths. zsh interactive `.zshrc` configuration and fish commands
guarded by `status is-interactive` are outside this initialization contract.

Keep greetd's `source_profile` enabled as the POSIX baseline, including for fish
and the greeter. Akari does not select startup files or branch on shell names.
Its forwarding expression uses `-l -c` and `exec "$VARIABLE"`; bash, sh, zsh,
and fish are exercised by native-shell tests. Other shells need to support that
invocation contract. Do not interpret native configuration with sh.

The native login shell can load a POSIX profile again through distribution or
user startup configuration. Those profiles must tolerate repeated evaluation;
this compatibility behavior is explicit rather than hidden by shell-specific
Akari exceptions. Existing installed greetd configurations are preserved by the
installer: remove an old `source_profile = false` setting when upgrading.

Preserve explicit user locale choices and their precedence. When no effective
locale is configured, use the distribution's locale, with an available UTF-8
fallback. Diagnose invalid configured locales rather than silently replacing
them. Preserve the initialized user's PATH after resolving the trusted desktop
entry executable.

The greetd transport quotes argv for its sh execution boundary. The native shell
receives a fixed expression that expands a quoted executor path. Desktop argv
and selection metadata travel as JSON in the greetd environment, so fish and
POSIX shells never reinterpret desktop arguments. The executor removes Akari's
internal variables before using `exec` for the selected command, preserving
process identity, signals, and exit status.

## Variables and publication

Require agreement only for variables that a desktop or dependent service needs;
the complete environments need not be identical. The user service manager is
shared across login sessions, whereas a compositor process belongs to one session.

| Variable group | Source and publication rule |
| --- | --- |
| Locale and executable search | Login initialization supplies `LANG`, `LANGUAGE`, configured `LC_*`, and PATH; the session owner publishes relevant values before service activation |
| Desktop identity | Selected desktop metadata supplies `XDG_CURRENT_DESKTOP`, `XDG_SESSION_DESKTOP`, and `XDG_SESSION_TYPE`; desktop-specific integration owns the final values |
| Toolkit, input method, and appearance | User/desktop configuration supplies an explicit set such as `QT_IM_MODULE`, `XMODIFIERS`, `QT_QPA_PLATFORMTHEME`, and cursor variables; publish those actually configured and required |
| Display and compositor instance | Compositor supplies `WAYLAND_DISPLAY`, optional `DISPLAY`/`XAUTHORITY`, and instance variables; publish after those values exist |
| Login resources and service-specific configuration | Preserve PAM/login context and existing user-unit configuration; do not copy an entire process environment into the shared activation environment |

Choose the published variable set from the supported desktop's actual needs.
Do not set input-method variables merely because an input method is installed.
Absent optional variables do not become required readiness conditions.

Do not globally publish transient login identifiers such as `XDG_SESSION_ID`,
`XDG_SEAT`, and `XDG_VTNR`. Do not propagate greeter `AKARI_*` internals or replace
the established user bus with the greeter's private bus.

`environment.d` configures environments for systemd user services; it does not
automatically initialize a compositor launched directly by greetd. A session
manager that bridges these environments must define its precedence. Akari must
not overwrite unrelated user-unit settings by importing a wholesale environment.

## Existing managers and direct compositor sessions

Preserve the user's selected desktop entry. GNOME, Plasma, and other managed
desktops retain their own session lifecycle. Akari must not start or restart
their graphical targets or portal services independently.

For a selected UWSM-managed entry, delegate publication, readiness, and cleanup
to UWSM. Its `finalize` mechanism and required-variable configuration provide
the integration points for compositor-specific values. Configure only variables
that are guaranteed to be supplied. Do not wrap an already managed entry in a
second manager or silently switch a plain Hyprland selection to UWSM.

A directly launched compositor retains its native integration. Additional
publication needs an explicit compositor hook executed after its configuration
and endpoints are ready. Successful publication must precede launching the
services that depend on it. For dbus-daemon with a systemd user manager,
`dbus-update-activation-environment --systemd` can update both stores; dbus-broker
already delegates activation environment management to systemd. Verify the
backend and results rather than infer them from the presence of one command.

A fixed sleep is not a readiness condition. Separate asynchronous launch calls
do not establish ordering even when they appear consecutively in Lua. An
integration must await successful publication before starting its dependent
processes, or use session-manager service dependencies and readiness checks.

The unmodified end-4 callbacks remain a compatibility limitation: a custom
callback can publish additional variables and sequence its own applications,
but cannot prevent upstream applications from starting earlier. Upstream does
not retain its callback subscription for custom removal. Full ordering requires
an actual startup extension point or a locally maintained loader/startup module
that replaces the relevant launches. Intercepting global `hl.on`/`hl.exec_cmd`
or filtering command strings is not an Akari integration strategy.

Akari can guarantee the prepared login environment in a direct session. It
cannot guarantee service ordering inside arbitrary user rice. Report that
boundary explicitly instead of describing eventual imports as a readiness gate.

## Lifecycle and diagnostics

The session owner records the activation values it changes and owns their
cleanup. Cleanup must not indiscriminately clear the user manager's environment
or overwrite a newer session's values. The reference dbus-daemon cannot unset
activation variables; document the manager's cleanup limitations.

Updating activation values affects future service launches only. Restart an
affected running service only as an explicit recovery action for that service,
not as routine login initialization. Configuration reload must not recreate a
session or restart unrelated applications.

Record startup stage, selected desktop entry, configured shell, publication
result, and the readiness owner in user-session diagnostics. Log only the
relevant variable names and necessary non-sensitive values. Keep user logs in
the user's XDG state directory, separate from greeter logs. Do not dump the
complete environment. See [login handoff experiments](login-handoff.md) for the
existing launcher and VT ownership boundary.

## Acceptance checks before implementation is considered complete

- Real greetd login with zsh and fish: login-only exported variables reach the
  desktop; interactive-only configuration is not executed.
- A clean login without terminal inheritance supplies the system locale and
  initialized PATH; explicit user locale choices remain effective.
- Quoted executable paths, spaces, empty arguments, and `sh -c` survive handoff.
- A compositor child, a newly started systemd user service, and a newly D-Bus
  activated service agree on the required variable set. Verify running service
  environments, not only `systemctl --user show-environment`.
- Delay publication deliberately: managed dependent services wait for the actual
  required values, and timeout/failure does not report successful readiness.
- Test UWSM-managed and direct Hyprland entries separately, including unmodified
  rice; retain the stated ordering limitation in direct rice sessions.
- Test dbus-broker and dbus-daemon behavior, logout/login, failed desktop startup,
  and configuration reload. Confirm cleanup and absence of duplicate autostarts.
- A second concurrent or nested compositor must not silently replace the first
  session's shared activation values; follow the selected manager's supported
  session model rather than inventing per-session isolation in systemd --user.
- Production and real-login test configurations follow the same initialization
  policy. Mock protocol tests alone do not establish environment propagation.

## References

- [greetd profile configuration](https://man.archlinux.org/man/greetd.5.en)
- [greetd shell command execution](https://github.com/kennylevinsen/greetd/blob/master/greetd/src/session/worker.rs)
- [SDDM shell-specific session initialization](https://github.com/sddm/sddm/blob/v0.21.0/data/scripts/wayland-session)
- [zsh startup files](https://zsh.sourceforge.io/Doc/Release/Files.html)
- [fish configuration](https://fishshell.com/docs/current/#configuration)
- [Hyprland 0.56.2 activation imports](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/Compositor.cpp)
- [Hyprland asynchronous Lua execution](https://wiki.hypr.land/configuring/core/advanced-configuration/lua-utilities/)
- [dbus-broker activation forwarding](https://github.com/bus1/dbus-broker/blob/main/src/launch/launcher.c)
- [D-Bus activation environment updates](https://dbus.freedesktop.org/doc/dbus-update-activation-environment.1.html)
- [systemd environment.d applicability](https://github.com/systemd/systemd/blob/main/man/environment.d.xml)
- [UWSM environment and readiness management](https://github.com/Vladimir-csp/uwsm#readme)
