#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"
repo_root="$(mozais_repo_root)"
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
if [[ ! -f "$repo_root/pubspec.yaml" ]]; then
  printf 'miss %-20s pubspec.yaml is missing\n' project
  missing=1
fi
if [[ ! -f "$repo_root/backend/Cargo.toml" ]]; then
  printf 'miss %-20s backend/Cargo.toml is missing\n' backend
  missing=1
fi

check_command cargo
check_command fvm
check_command dbus-run-session
check_command busctl
check_command clang
check_command cmake
check_command ninja
check_command pkg-config

if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists gtk+-3.0; then
  printf 'ok   %-20s GTK 3 development files\n' gtk+-3.0
else
  printf 'miss %-20s install the gtk3 package\n' gtk+-3.0
  missing=1
fi

if command -v cargo >/dev/null 2>&1 && [[ -f "$repo_root/backend/Cargo.toml" ]]; then
  if cargo metadata \
    --manifest-path "$repo_root/backend/Cargo.toml" \
    --locked \
    --no-deps \
    --format-version 1 >/dev/null 2>&1; then
    printf 'ok   %-20s backend manifest\n' cargo-metadata
  else
    printf 'miss %-20s backend manifest is invalid\n' cargo-metadata
    missing=1
  fi
fi

if [[ -x "$repo_root/.fvm/flutter_sdk/bin/flutter" ]]; then
  flutter_version=''
  if flutter_version="$("$repo_root/.fvm/flutter_sdk/bin/flutter" --version 2>&1)"; then
    printf 'ok   %-20s %s\n' flutter "$repo_root/.fvm/flutter_sdk/bin/flutter"
    sed -n '1,3p' <<<"$flutter_version"
  else
    printf '%s\n' "$flutter_version" | sed -n '1,3p' >&2
    printf 'miss %-20s Flutter SDK exists but could not run\n' flutter
    missing=1
  fi
else
  printf 'miss %-20s run scripts/bootstrap-toolchain.sh first\n' flutter
  missing=1
fi

check_command sway
check_command greetd

if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  printf 'ok   %-20s %s\n' WAYLAND_DISPLAY "$WAYLAND_DISPLAY"
else
  printf 'warn %-20s not set; nested Sway debug needs a Wayland desktop\n' WAYLAND_DISPLAY
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi
