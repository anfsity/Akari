#!/usr/bin/env bash
set -uo pipefail
frontend_pid=''
watcher_pid=''
cleanup() {
  for child in "$watcher_pid" "$frontend_pid"; do
    if [[ -n "$child" ]]; then
      kill "$child" >/dev/null 2>&1 || true
      wait "$child" >/dev/null 2>&1 || true
    fi
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
      kill "$frontend_pid" >/dev/null 2>&1 || true
      break
    fi
    sleep 1
  done
) &
watcher_pid=$!
wait "$frontend_pid"
status=$?
printf 'Frontend exited: %s\n' "$status" >> "$AKARI_LOG_DIR/lifecycle.log"
exit "$status"
