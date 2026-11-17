#!/usr/bin/env bash
set -uo pipefail
exec >> "$AKARI_LOG_DIR/lifecycle.log" 2>&1
frontend_pid=''
watcher_pid=''
is_pid_running() {
  local pid="$1" line
  kill -0 "$pid" >/dev/null 2>&1 || return 1
  if [[ -e "/proc/$pid/status" ]]; then
    while IFS= read -r line; do
      if [[ "$line" == State:* ]]; then
        [[ "$line" != $'State:\tZ'* && "$line" != $'State:\tX'* && "$line" != $'State:\tx'* ]]
        return
      fi
    done < "/proc/$pid/status" 2>/dev/null || return 1
  fi
  return 0
}

terminate_child() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    return 0
  fi
  if is_pid_running "$pid"; then
    kill "$pid" >/dev/null 2>&1 || true
    for _ in {1..30}; do
      if ! is_pid_running "$pid"; then
        break
      fi
      sleep 0.1
    done
    if is_pid_running "$pid"; then
      kill -KILL "$pid" >/dev/null 2>&1 || true
    fi
  fi
  wait "$pid" >/dev/null 2>&1 || true
}

cleanup() {
  for child in "$watcher_pid" "$frontend_pid"; do
    terminate_child "$child"
  done
  swaymsg exit >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

python3 "$AKARI_RELEASE/display-layout.py" run /etc/akari/display-layout.json \
  "$AKARI_APP" > "$AKARI_LOG_DIR/flutter.log" 2>&1 &
frontend_pid=$!
# The backend exits both on session handoff and on fatal errors. Releasing
# Sway in either case lets greetd start the desktop or offer a fresh greeter.
(
  while is_pid_running "$frontend_pid"; do
    if ! busctl --user status io.akari.Greeter >/dev/null 2>&1; then
      terminate_child "$frontend_pid"
      break
    fi
    sleep 0.2
  done
) &
watcher_pid=$!
wait "$frontend_pid"
status=$?
printf 'Frontend exited: %s\n' "$status"
exit "$status"
