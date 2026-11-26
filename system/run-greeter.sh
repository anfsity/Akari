#!/usr/bin/env bash
set -uo pipefail
exec >> "$AKARI_LOG_DIR/lifecycle.log" 2>&1
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$script_dir/scripts/lib.sh" ]]; then
  # shellcheck source=../scripts/lib.sh
  source "$script_dir/scripts/lib.sh"
else
  # shellcheck source=../scripts/lib.sh
  source "$script_dir/../scripts/lib.sh"
fi
frontend_pid=''
watcher_pid=''

cleanup() {
  for child in "$watcher_pid" "$frontend_pid"; do
    akari_terminate_pid "$child"
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
  while akari_is_pid_running "$frontend_pid"; do
    if ! busctl --user status io.akari.Greeter >/dev/null 2>&1; then
      akari_stop_pid "$frontend_pid"
      break
    fi
    sleep 0.2
  done
) &
watcher_pid=$!
wait "$frontend_pid"
status=$?
frontend_pid=''
printf 'Frontend exited: %s\n' "$status"
exit "$status"
