#!/usr/bin/env bash
set -euo pipefail
# Pin one release for the entire greeter lifetime, including an upgrade while
# the current login screen or user session is still running.
export AKARI_RELEASE="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
umask 022
log_root="/var/log/akari/greeter"
shopt -s nullglob
old_sessions=( "$log_root"/session-* )
shopt -u nullglob
if (( ${#old_sessions[@]} >= 20 )); then
  mapfile -t sorted_sessions < <(ls -1dt -- "${old_sessions[@]}" 2>/dev/null)
  for stale in "${sorted_sessions[@]:19}"; do
    [[ -L "$stale" ]] || rm -rf -- "$stale"
  done
fi
export AKARI_LOG_DIR="$(mktemp -d "$log_root/session-XXXXXXXX")"
exec >> "$AKARI_LOG_DIR/lifecycle.log" 2>&1
chmod 0755 "$AKARI_LOG_DIR"
export AKARI_BACKEND_MODE=real
export AKARI_BACKEND_BIN="$AKARI_RELEASE/backend"
export AKARI_SPLASH_BIN="$AKARI_RELEASE/akari-splash"
export AKARI_APP="$AKARI_RELEASE/frontend/greeter"
export AKARI_WINDOW_MODE=fullscreen
export XDG_STATE_HOME=/var/lib/akari/greeter
export GDK_BACKEND=wayland
export XDG_CURRENT_DESKTOP=Sway
export XDG_SESSION_DESKTOP=sway
export XDG_SESSION_TYPE=wayland
unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET SWAYSOCK WLR_BACKENDS WLR_WAYLAND_DISPLAY
sway_bin=/usr/bin/sway
if [[ ! -x "$sway_bin" ]] && command -v sway >/dev/null 2>&1; then
  sway_bin="$(command -v sway)"
fi
exec "$AKARI_RELEASE/scripts/debug-dbus.sh" \
  /bin/bash "$AKARI_RELEASE/scripts/splash.sh" \
  /bin/sh -c 'exec "$@" > "$AKARI_LOG_DIR/sway.log" 2>&1' _ "$sway_bin" --config /etc/akari/sway.conf
