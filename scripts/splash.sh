#!/usr/bin/env bash
set -euo pipefail

# Run on the private bus after backend readiness, keeping bus startup out of
# the gap after the animation. wait acknowledges DRM release before startup.
splash_pid=''
compositor_pid=''
splash_status=0
cleanup() {
  trap '' INT TERM HUP
  for child in "$splash_pid" "$compositor_pid"; do
    if [[ -n "$child" ]]; then
      kill "$child" 2>/dev/null || true
      wait "$child" 2>/dev/null || true
    fi
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
