#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
log_dir="$repo_root/logs"

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  printf '%s\n' 'WAYLAND_DISPLAY is not set; run this from a Wayland desktop.' >&2
  exit 1
fi

if [[ ! -f "$repo_root/pubspec.yaml" ]]; then
  printf '%s\n' 'pubspec.yaml is missing; run scripts/bootstrap-toolchain.sh first.' >&2
  exit 1
fi

mkdir -p "$log_dir"
cd -- "$repo_root"
fvm flutter build linux --debug --dart-define=MOZAIS_BACKEND=mock "$@"

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

exec dbus-run-session -- env \
  MOZAIS_BUS_MODE=private \
  G_MESSAGES_DEBUG=all \
  sway -d -c "$repo_root/config/sway/debug.conf" \
  >"$log_dir/sway-debug.log" 2>&1
