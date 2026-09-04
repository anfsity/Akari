#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
missing=0

check_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok   %-20s %s\n' "$command_name" "$(command -v "$command_name")"
  else
    printf 'miss %-20s\n' "$command_name"
    missing=1
  fi
}

printf '%s\n' "Mozais toolchain: $repo_root"
check_command dart
check_command fvm
check_command dbus-run-session
check_command busctl
check_command gdb
check_command sway
check_command greetd

if [[ -x "$repo_root/.fvm/flutter_sdk/bin/flutter" ]]; then
  printf 'ok   %-20s %s\n' flutter "$repo_root/.fvm/flutter_sdk/bin/flutter"
  "$repo_root/.fvm/flutter_sdk/bin/flutter" --version | sed -n '1,3p'
else
  printf 'miss %-20s run scripts/bootstrap-toolchain.sh first\n' flutter
  missing=1
fi

if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  printf 'ok   %-20s %s\n' WAYLAND_DISPLAY "$WAYLAND_DISPLAY"
else
  printf 'warn %-20s not set; nested Sway debug needs a Wayland desktop\n' WAYLAND_DISPLAY
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi
