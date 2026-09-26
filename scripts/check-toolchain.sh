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

flutter_command=(fvm flutter)
dart_command=(fvm dart)
custom_flutter="${MOZAIS_FLUTTER_BIN:-}"
custom_dart="${MOZAIS_DART_BIN:-}"

if [[ -n "$custom_flutter" ]]; then
  if [[ "$custom_flutter" != /* ]]; then
    custom_flutter="$repo_root/$custom_flutter"
  fi
  flutter_command=("$custom_flutter")
  if [[ -z "$custom_dart" ]]; then
    custom_dart="$(dirname -- "$custom_flutter")/dart"
  fi
fi

if [[ -n "$custom_dart" ]]; then
  if [[ "$custom_dart" != /* ]]; then
    custom_dart="$repo_root/$custom_dart"
  fi
  dart_command=("$custom_dart")
fi

if [[ "${flutter_command[0]}" == fvm || "${dart_command[0]}" == fvm ]]; then
  check_command fvm
fi

check_sdk() {
  local sdk_name="$1"
  shift
  local sdk_version=''

  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'miss %-20s %s\n' "$sdk_name" "${1} is unavailable"
    missing=1
    return
  fi

  if sdk_version="$("$@" --version 2>&1)"; then
    printf 'ok   %-20s %s\n' "$sdk_name" "$*"
    sed -n '1,3p' <<<"$sdk_version"
  else
    printf '%s\n' "$sdk_version" | sed -n '1,3p' >&2
    printf 'miss %-20s SDK could not run\n' "$sdk_name"
    missing=1
  fi
}

check_sdk flutter "${flutter_command[@]}"
check_sdk dart "${dart_command[@]}"

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
