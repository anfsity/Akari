#!/usr/bin/env bash
set -euo pipefail

# Run on the private bus after backend readiness, keeping bus startup out of
# the gap after the animation. wait acknowledges DRM release before exec.
splash_pid=''
splash_status=0
trap 'if [[ -n "$splash_pid" ]]; then kill "$splash_pid" 2>/dev/null || true; wait "$splash_pid" 2>/dev/null || true; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
AKARI_SPLASH_PARENT_PID="$$" "$AKARI_SPLASH_BIN" kms \
  --snapshot "$AKARI_LOG_DIR/splash.png" >> "$AKARI_LOG_DIR/lifecycle.log" 2>&1 &
splash_pid=$!
wait "$splash_pid" || splash_status=$?
splash_pid=''
trap - EXIT INT TERM HUP
printf 'event=splash_finished status=%s\n' "$splash_status" >> "$AKARI_LOG_DIR/lifecycle.log"
exec "$@"
