#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  printf '%s\n' 'WAYLAND_DISPLAY is not set; run this from a Wayland desktop.' >&2
  exit 1
fi

if [[ ! -f "$repo_root/pubspec.yaml" ]]; then
  printf '%s\n' 'pubspec.yaml is missing; run scripts/bootstrap-toolchain.sh first.' >&2
  exit 1
fi

if [[ "${MOZAIS_PRIVATE_BUS:-0}" != 1 ]]; then
  exec "$script_dir/debug-dbus.sh" "$script_dir/debug-sway.sh" "$@"
fi

log_dir="${MOZAIS_LOG_DIR:-$repo_root/logs}"

mkdir -p "$log_dir"
cd -- "$repo_root"
backend="${MOZAIS_BACKEND:-mock}"
case "$backend" in
  mock|real)
    ;;
  *)
    printf 'MOZAIS_BACKEND must be mock or real, got: %s\n' "$backend" >&2
    exit 2
    ;;
esac

fvm flutter build linux --debug --dart-define="MOZAIS_BACKEND=$backend" "$@"

app="$repo_root/build/linux/x64/debug/bundle/mozais_greeter"
if [[ ! -x "$app" ]]; then
  printf 'Flutter bundle was not found: %s\n' "$app" >&2
  exit 1
fi

export MOZAIS_APP="$app"
export MOZAIS_FLUTTER_LOG="$log_dir/flutter-debug.log"
export GDK_BACKEND=wayland
export WLR_BACKENDS=wayland
export WLR_WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
export XDG_CURRENT_DESKTOP=Sway
export XDG_SESSION_DESKTOP=sway
export XDG_SESSION_TYPE=wayland

exec sway -d -c "$repo_root/config/sway/debug.conf" \
  >"$log_dir/sway-debug.log" 2>&1
