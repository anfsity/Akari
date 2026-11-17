#!/usr/bin/env bash
set -euo pipefail

# Run on the private bus after backend readiness, keeping bus startup out of
# the gap after the animation. wait acknowledges DRM release before startup.
splash_pid=''
compositor_pid=''
splash_status=0
is_pid_running() {
  local pid="$1" line
  kill -0 "$pid" 2>/dev/null || return 1
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
    kill "$pid" 2>/dev/null || true
    for _ in {1..30}; do
      if ! is_pid_running "$pid"; then
        break
      fi
      sleep 0.1
    done
    if is_pid_running "$pid"; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  wait "$pid" 2>/dev/null || true
}

cleanup() {
  trap '' INT TERM HUP
  for child in "$splash_pid" "$compositor_pid"; do
    terminate_child "$child"
  done
  # Sway exec children have no controlling terminal. Keep VT cleanup in this
  # launcher, which retains greetd's terminal until the compositor has exited.
  "$AKARI_SPLASH_BIN" clear >> "$AKARI_LOG_DIR/lifecycle.log" 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
AKARI_SPLASH_PARENT_PID="$$" "$AKARI_SPLASH_BIN" kms \
  --snapshot "$AKARI_LOG_DIR/splash.png" >> "$AKARI_LOG_DIR/lifecycle.log" 2>&1 &
splash_pid=$!
wait "$splash_pid" || splash_status=$?
splash_pid=''
printf 'event=splash_finished status=%s\n' "$splash_status" >> "$AKARI_LOG_DIR/lifecycle.log"
"$@" <&0 &
compositor_pid=$!
wait "$compositor_pid"
