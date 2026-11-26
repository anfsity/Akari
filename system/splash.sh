#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$script_dir/lib.sh" ]]; then
  # shellcheck source=../scripts/lib.sh
  source "$script_dir/lib.sh"
else
  # shellcheck source=../scripts/lib.sh
  source "$script_dir/../scripts/lib.sh"
fi

# Run on the private bus after backend readiness, keeping bus startup out of
# the gap after the animation. wait acknowledges DRM release before startup.
splash_pid=''
compositor_pid=''
splash_status=0

cleanup() {
  trap '' INT TERM HUP
  for child in "$splash_pid" "$compositor_pid"; do
    akari_terminate_pid "$child"
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
compositor_status=0
wait "$compositor_pid" || compositor_status=$?
compositor_pid=''
exit "$compositor_status"
