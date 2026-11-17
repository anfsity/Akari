#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"
repo_root="$(akari_repo_root)"
missing=0
require_runtime=0

for arg in "$@"; do
  case "$arg" in
    --runtime)
      require_runtime=1
      ;;
    --help|-h)
      printf 'Usage: %s [--runtime]\n' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

check_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok   %-20s %s\n' "$command_name" "$(command -v "$command_name")"
  else
    printf 'miss %-20s\n' "$command_name"
    missing=1
  fi
}

check_runtime_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok   %-20s %s\n' "$command_name" "$(command -v "$command_name")"
  elif [[ "$require_runtime" -eq 1 ]]; then
    printf 'miss %-20s\n' "$command_name"
    missing=1
  else
    printf 'warn %-20s not installed; needed for Sway/greetd runtime targets\n' "$command_name"
  fi
}

check_pkg_config() {
  local module_name="$1"
  local description="$2"
  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists "$module_name"; then
    printf 'ok   %-20s %s\n' "$module_name" "$description"
  else
    printf 'miss %-20s install %s\n' "$module_name" "$description"
    missing=1
  fi
}

printf '%s\n' "Akari toolchain: $repo_root"
if [[ ! -f "$repo_root/apps/greeter/pubspec.yaml" ]]; then
  printf 'miss %-20s apps/greeter/pubspec.yaml is missing\n' project
  missing=1
fi
if [[ ! -f "$repo_root/crates/akari-backend/Cargo.toml" ]]; then
  printf 'miss %-20s crates/akari-backend/Cargo.toml is missing\n' backend
  missing=1
fi

check_command cargo
check_command python3
check_command dbus-daemon
check_command busctl
check_command setpriv
check_command setsid
check_command clang
check_command cmake
check_command ninja
check_command pkg-config
check_pkg_config libseat 'libseat development files'
check_pkg_config gtk+-3.0 'GTK 3 development files'
check_pkg_config epoxy 'libepoxy development files'

if command -v cargo >/dev/null 2>&1 && [[ -f "$repo_root/crates/akari-backend/Cargo.toml" ]]; then
  if cargo metadata \
    --manifest-path "$repo_root/crates/akari-backend/Cargo.toml" \
    --locked \
    --no-deps \
    --format-version 1 >/dev/null 2>&1; then
    printf 'ok   %-20s backend manifest\n' cargo-metadata
  else
    printf 'miss %-20s backend manifest is invalid\n' cargo-metadata
    missing=1
  fi
fi

akari_resolve_sdk_binaries "$repo_root"
flutter_command=(fvm flutter)
dart_command=(fvm dart)

if [[ -n "${AKARI_RESOLVED_FLUTTER_BIN:-}" && -x "$AKARI_RESOLVED_FLUTTER_BIN" ]]; then
  flutter_command=("$AKARI_RESOLVED_FLUTTER_BIN")
fi

if [[ -n "${AKARI_RESOLVED_DART_BIN:-}" && -x "$AKARI_RESOLVED_DART_BIN" ]]; then
  dart_command=("$AKARI_RESOLVED_DART_BIN")
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

check_runtime_command sway
check_runtime_command swaybg
check_runtime_command grim
check_runtime_command greetd

if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  printf 'ok   %-20s %s\n' WAYLAND_DISPLAY "$WAYLAND_DISPLAY"
else
  printf 'warn %-20s not set; nested Sway debug needs a Wayland desktop\n' WAYLAND_DISPLAY
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi
