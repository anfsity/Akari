#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"
repo_root="$(mozais_repo_root)"

usage() {
  printf '%s\n' \
    'Usage: scripts/debug-dbus.sh [command [args...]]' \
    '  Starts the mock backend and command on one private D-Bus session.' \
    '  With no command, runs scripts/debug-ui.sh.' \
    'Environment:' \
    '  MOZAIS_BACKEND_MODE=mock|real   Backend transport (default: mock).' \
    '  MOZAIS_START_BACKEND=0|1        Skip or start the backend (default: 1).' \
    '  MOZAIS_LOG_DIR=PATH              Reuse an explicit log directory.'
}

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  usage
  exit 0
fi

inside_private_bus=0
if [[ "${1:-}" == --inside-private-bus ]]; then
  inside_private_bus=1
  shift
fi

if [[ "$inside_private_bus" -eq 0 ]]; then
  if [[ -z "${MOZAIS_LOG_DIR:-}" ]]; then
    export MOZAIS_LOG_DIR="$repo_root/logs/debug-$(date +%Y%m%d-%H%M%S)-$$"
  fi
  log_dir="$(mozais_log_dir "$repo_root")"
  export MOZAIS_PRIVATE_BUS=1
  exec dbus-run-session -- "$script_dir/debug-dbus.sh" --inside-private-bus "$@"
fi

if [[ "${MOZAIS_PRIVATE_BUS:-0}" != 1 ]]; then
  printf '%s\n' 'Internal error: private D-Bus marker is missing.' >&2
  exit 1
fi

log_dir="$(mozais_log_dir "$repo_root")"
backend_pid=''

cleanup() {
  if [[ -n "$backend_pid" ]] && kill -0 "$backend_pid" >/dev/null 2>&1; then
    kill "$backend_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$backend_pid" ]]; then
    wait "$backend_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

start_backend="${MOZAIS_START_BACKEND:-1}"
if [[ "$start_backend" != 0 && "$start_backend" != 1 ]]; then
  printf 'MOZAIS_START_BACKEND must be 0 or 1, got: %s\n' "$start_backend" >&2
  exit 2
fi

if [[ "$start_backend" -eq 1 ]]; then
  backend_mode="${MOZAIS_BACKEND_MODE:-mock}"
  case "$backend_mode" in
    mock|real)
      ;;
    *)
      printf 'MOZAIS_BACKEND_MODE must be mock or real, got: %s\n' "$backend_mode" >&2
      exit 2
      ;;
  esac

  mozais_require_command busctl
  "$script_dir/run-backend.sh" "--$backend_mode" >"$log_dir/backend.log" 2>&1 &
  backend_pid=$!

  backend_ready=0
  for _ in {1..100}; do
    if ! kill -0 "$backend_pid" >/dev/null 2>&1; then
      printf '%s\n' 'Backend exited before registering on the private D-Bus.' >&2
      tail -n 40 "$log_dir/backend.log" >&2 || true
      exit 1
    fi
    if busctl --user introspect \
      io.mozais.Greeter \
      /io/mozais/Greeter \
      io.mozais.Greeter1 >/dev/null 2>&1; then
      backend_ready=1
      break
    fi
    sleep 0.1
  done

  if [[ "$backend_ready" -ne 1 ]]; then
    printf '%s\n' 'Timed out waiting for the backend on the private D-Bus.' >&2
    tail -n 40 "$log_dir/backend.log" >&2 || true
    exit 1
  fi
fi

if [[ "$#" -eq 0 ]]; then
  set -- "$script_dir/debug-ui.sh"
fi

export MOZAIS_BUS_MODE=private
export RUST_LOG="${RUST_LOG:-backend=info,warn}"
"$@"
