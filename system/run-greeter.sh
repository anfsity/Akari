#!/usr/bin/env bash
set -uo pipefail
exec >> "$AKARI_LOG_DIR/lifecycle.log" 2>&1
frontend_pid=''
watcher_pid=''
terminate_child() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    return 0
  fi
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    for _ in {1..30}; do
      if ! kill -0 "$pid" >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done
    if kill -0 "$pid" >/dev/null 2>&1; then
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
  while kill -0 "$frontend_pid" >/dev/null 2>&1; do
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
