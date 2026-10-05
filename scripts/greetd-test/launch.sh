#!/usr/bin/env bash
set -euo pipefail
test_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
run_dir="$(readlink -f "$test_root/current-run")"
# greetd can launch several greeters in one test. Each owns a separate directory
# so a later login screen cannot overwrite the first handoff's backend logs.
umask 022
export AKARI_LOG_DIR="$(mktemp -d "$run_dir/greeter/session-XXXXXXXX")"
chmod 0755 "$AKARI_LOG_DIR"
export AKARI_BACKEND_MODE=real
export AKARI_BACKEND_BIN="$test_root/backend"
export AKARI_APP="$test_root/frontend/greeter"
export AKARI_FLUTTER_LOG="$AKARI_LOG_DIR/flutter.log"
export AKARI_WINDOW_MODE=fullscreen
export AKARI_DISPLAY_LAYOUT="$test_root/display-layout.json"
export AKARI_DISPLAY_LAYOUT_RUNNER="$test_root/display-layout.py"
export AKARI_DISPLAY_SOURCE=greetd-login
export AKARI_TEST_RUN="$run_dir"
export XDG_STATE_HOME="$test_root/state"
export GDK_BACKEND=wayland
export XDG_CURRENT_DESKTOP=Sway
export XDG_SESSION_DESKTOP=sway
export XDG_SESSION_TYPE=wayland
# This is a standalone DRM test. Do not inherit nested desktop backend settings.
unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET SWAYSOCK WLR_BACKENDS WLR_WAYLAND_DISPLAY
exec "$test_root/scripts/debug-dbus.sh" \
  /usr/bin/sway --config "$run_dir/sway.conf" > "$AKARI_LOG_DIR/sway.log" 2>&1
