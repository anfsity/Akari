#!/usr/bin/env bash
set -euo pipefail
# Pin one release for the entire greeter lifetime, including an upgrade while
# the current login screen or user session is still running.
export AKARI_RELEASE="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
umask 022
export AKARI_LOG_DIR="$(mktemp -d /var/log/akari/greeter/session-XXXXXXXX)"
export AKARI_BACKEND_MODE=real
export AKARI_BACKEND_BIN="$AKARI_RELEASE/backend"
export AKARI_APP="$AKARI_RELEASE/frontend/greeter"
export AKARI_BUS_MODE=private
export AKARI_WINDOW_MODE=fullscreen
export XDG_STATE_HOME=/var/lib/akari/greeter
export GDK_BACKEND=wayland
export XDG_CURRENT_DESKTOP=Sway
export XDG_SESSION_DESKTOP=sway
export XDG_SESSION_TYPE=wayland
unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET SWAYSOCK WLR_BACKENDS WLR_WAYLAND_DISPLAY
printf 'Akari greeter logs: %s\n' "$AKARI_LOG_DIR"
exec "$AKARI_RELEASE/scripts/debug-dbus.sh" \
  /usr/bin/sway --config /etc/akari/sway.conf > "$AKARI_LOG_DIR/sway.log" 2>&1
