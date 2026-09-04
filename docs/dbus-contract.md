# Architectural Analysis: Mozais D-Bus Contract

This specification defines the inter-process communication (IPC) boundaries, state machine invariants, security policies, and technical implementations for the **Mozais Greeter** backend-frontend abstraction layer.

---

## 1. System Architecture & Component Separation

The architecture decouples the user interface (Flutter client) from underlying system daemons (`greetd` and `systemd-logind`) using a dedicated, unprivileged backend bridge.

```text
┌───────────────────────────────────────────────────────────┐
│                    Flutter UI Client                      │
│            (Unprivileged / Non-root User)                 │
└─────────────────────────────┬─────────────────────────────┘
                              │
                              │ Private / Session D-Bus
                              │ Bus: io.mozais.Greeter
                              │ Interface: io.mozais.Greeter1
                              ▼
┌───────────────────────────────────────────────────────────┐
│              Mozais Backend Bridge Daemon                 │
│         (Translates D-Bus Calls to greetd / System)       │
└──────────────┬─────────────────────────────┬──────────────┘
               │                             │
               │ Unix Domain Socket          │ System D-Bus
               │ (4-byte LE framing + JSON)  │ (org.freedesktop.login1)
               ▼                             ▼
┌─────────────────────────────┐   ┌─────────────────────────┐
│           greetd            │   │     systemd-logind      │
│   (PAM Authentication)      │   │   (Power Management)    │
└─────────────────────────────┘   └─────────────────────────┘
```

### Architectural Benefits
* **Framework Isolation**: The Flutter frontend remains agnostic of Unix domain sockets, PAM message formats, binary frame packing, and `systemd` DBus interfaces.
* **Testability**: The backend interface can be replaced with a mock service (`MOZAIS_BACKEND=mock`) on a private D-Bus session (`dbus-run-session`), allowing complete UI development without running a real `greetd` daemon or elevated privileges.
* **Least Privilege Enforcement**: The UI runs as an unprivileged client with no direct access to root or system-level control interfaces.

---

## 2. Interface Specification: `io.mozais.Greeter1`

### Service Coordinates
* **Bus Name**: `io.mozais.Greeter`
* **Object Path**: `/io/mozais/Greeter`
* **Interface**: `io.mozais.Greeter1`

---

### Methods Specification

#### Query Operations

##### `GetState() -> (String state, String detail)`
* **Description**: Returns the current state of the backend authentication engine.
* **Returns**:
  * `state`: The high-level state enum (e.g., `Idle`, `Authenticating`, `Authenticated`, `Error`).
  * `detail`: Additional status metadata or error message.

##### `ListUsers() -> Array<Struct<String, String, String>>`
* **Description**: Enumerates system users available for login.
* **Returns**: Array of user records containing `username`, `display_name`, and `icon_path`.

##### `ListSessions() -> Array<Struct<String, String, String>>`
* **Description**: Parses and returns available Wayland and X11 sessions from `/usr/share/wayland-sessions` and `/usr/share/xsessions`.
* **Returns**: Array of session records containing `session_id`, `name`, and `desktop_names` (e.g., `["sway"]`, `["Hyprland"]`).

---

#### Authentication Lifecycle Operations

##### `BeginAuthentication(String username) -> String attempt_id`
* **Description**: Initiates a PAM authentication transaction for the specified `username`.
* **Behavior**:
  * Invalidates any existing active authentication attempts.
  * Connects to the underlying `greetd` socket and sends `create_session`.
  * Generates and returns a unique `attempt_id` (UUID v4 or monotonic token).

##### `Respond(String attempt_id, String response) -> Void`
* **Description**: Submits credential input (e.g., password or OTP token) for an ongoing PAM challenge.
* **Parameters**:
  * `attempt_id`: The transaction token returned by `BeginAuthentication`.
  * `response`: The plaintext response string (must be zeroed out in memory after processing).

##### `Cancel(String attempt_id) -> Void`
* **Description**: Explicitly aborts an active authentication transaction.
* **Behavior**: Sends `cancel_session` to `greetd` and resets the backend state machine to `Idle`.

##### `StartSession(String attempt_id, String session_id) -> Void`
* **Description**: Requests the execution of the selected desktop environment upon successful PAM authentication.
* **Parameters**:
  * `attempt_id`: Valid token for a currently `Authenticated` session.
  * `session_id`: The identifier corresponding to a session returned by `ListSessions()`.

---

#### Power Management Operations

##### `PowerAction(String action) -> Void`
* **Description**: Requests system power state changes (`PowerOff`, `Reboot`, `Suspend`, `Hibernate`).
* **Behavior**: The backend proxies the action to `systemd-logind` via the System D-Bus (`org.freedesktop.login1`).

---

### Signals Specification

##### `Prompt(String attempt_id, String prompt_kind, String text)`
* **Description**: Emitted asynchronously when PAM requires user input.
* **Parameters**:
  * `attempt_id`: The associated authentication transaction token.
  * `prompt_kind`: Enum indicating input type (`visible` for plain text, `secret` for passwords, `info` for informational text, `error` for PAM errors).
  * `text`: The prompt string provided by PAM (e.g., `"Password: "`).

##### `StateChanged(String attempt_id, String state, String detail)`
* **Description**: Emitted when the authentication engine transitions between internal states.
* **Parameters**:
  * `attempt_id`: The associated authentication transaction token.
  * `state`: New state string (`Idle`, `Authenticating`, `Authenticated`, `StartingSession`, `Failed`).
  * `detail`: Explanatory message or failure reason (e.g., `"Authentication failed"`).

---

## 3. The `attempt_id` Transaction Design

To prevent race conditions, stale UI responses, and replay attacks, all state-modifying operations require a unique `attempt_id`.

```text
[UI] --- BeginAuthentication("alice") ---> [Backend] (Generates token "att_01")
                                             │
[UI] <--- Prompt("att_01", "secret") ------- [Backend]
                                             │
[UI] --- Respond("att_01", "*****") ------> [Backend] (Valid: matches active att_01)
                                             │
[UI] --- Respond("att_00", "*****") ------> [Backend] (REJECTED: Stale attempt ID)
```

### Invariants
1. **Single Active Transaction**: The backend allows **exactly one** active `attempt_id` at a time. Issuing `BeginAuthentication` while another attempt is in progress automatically cancels the previous attempt.
2. **Stale Token Rejection**: Any `Respond()`, `Cancel()`, or `StartSession()` call containing a mismatched or expired `attempt_id` is immediately rejected without forwarding commands to PAM/`greetd`.

---

## 4. Security Policies & Boundaries

### 1. Zero-Trace Secret Handling
* **No Logging**: Passwords, response tokens, and raw PAM secret prompts must never be written to stdout, stderr, persistent logs, or ephemeral debug logs (`/tmp/mozais-flutter.log`, `/tmp/sway-debug.log`).
* **No Signal Exposure**: Secrets must only pass through the unicast D-Bus method call `Respond()`. Secrets must never be emitted via D-Bus Signals.
* **Crash Dump Exclusion**: Secret buffer memory should be marked with `MADV_DONTDUMP` where possible and zeroed out immediately after transmition over the socket.

### 2. D-Bus Bus Segregation & Privilege Model
* **Session/Private Bus**: Used exclusively for UI-to-Backend communication.
* **System Bus Isolation**: System-level actions (`PowerAction`) must be routed over the System Bus to `systemd-logind`.
* **Polkit Authorization**: Power actions must rely on `polkit` policies defined at `/usr/share/polkit-1/actions/` to grant or restrict shutdown/reboot privileges to the `greeter` user without requiring `sudo` or `setuid` binaries.
* **Unprivileged Backend Execution**: The backend daemon runs under the unprivileged `greeter` system user account (belonging to groups `greeter`, `video`, `render`).

---

## 5. State Machine Invariants

The backend engine maintains a deterministic finite state machine (FSM):

```text
┌──────┐  BeginAuthentication()  ┌────────────────┐  Prompt(secret)  ┌──────────────────┐
│ Idle │ ──────────────────────> │ CreatingSession│ ───────────────> │  Authenticating  │
└──────┘                         └────────────────┘                  └────────┬─────────┘
   ▲                                                                          │
   │                              Respond() / PAM Result                      │
   │                                                                          │
   │  Cancel() / Error            ┌──────────────┐                            │
   ├───────────────────────────── │ AuthFailed   │ <────── (Failure) ─────────┤
   │                              └──────────────┘                            │
   │                                                                          │
   │                              ┌──────────────┐                            │
   │  StartSession() Success      │ Authenticated│ <────── (Success) ─────────┘
   └───────────────────────────── └──────┬───────┘
                                         │
                                         │ StartSession()
                                         ▼
                                ┌────────────────┐
                                │ StartingSession│ (Executes session, exits greeter)
                                └────────────────┘
```

---

## 6. Development Workflow & Client Implementation

### Mock Backend Strategy
During local development, running `scripts/debug-ui.sh` initializes a private D-Bus session (`dbus-run-session`) and passes `--dart-define=MOZAIS_BACKEND=mock`. 

In mock mode:
1. The client connects to the mock implementation of `io.mozais.Greeter1`.
2. `ListUsers()` returns stubbed test users.
3. `ListSessions()` returns fake session entries (e.g., "Sway", "Hyprland").
4. `Respond()` validates against a mock password without opening a system PAM transaction or talking to `greetd`.