#!/usr/bin/env bash

# Shared helpers for scripts invoked from any working directory.

akari_repo_root() {
  local caller_path="${BASH_SOURCE[1]}"
  cd -- "$(dirname -- "$caller_path")/.." && pwd
}

akari_require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    return 1
  fi
}

akari_require_file() {
  local file_path="$1"
  local description="$2"
  if [[ ! -f "$file_path" ]]; then
    printf 'Missing %s: %s\n' "$description" "$file_path" >&2
    return 1
  fi
}

akari_log_dir() {
  local repo_root="$1"
  local log_dir="${AKARI_LOG_DIR:-$repo_root/logs}"
  mkdir -p -- "$log_dir"
  printf '%s\n' "$log_dir"
}

akari_resolve_sdk_binaries() {
  local repo_root="$1"
  local flutter_bin="${AKARI_FLUTTER_BIN:-}"
  if [[ -n "$flutter_bin" && "$flutter_bin" != /* ]]; then
    flutter_bin="$repo_root/$flutter_bin"
  fi

  local dart_bin="${AKARI_DART_BIN:-}"
  if [[ -n "$dart_bin" && "$dart_bin" != /* ]]; then
    dart_bin="$repo_root/$dart_bin"
  fi
  if [[ -z "$dart_bin" && -n "$flutter_bin" ]]; then
    dart_bin="$(dirname -- "$flutter_bin")/dart"
  fi
  if [[ -z "$flutter_bin" && -x "$repo_root/.fvm/flutter_sdk/bin/flutter" ]]; then
    flutter_bin="$repo_root/.fvm/flutter_sdk/bin/flutter"
  fi
  if [[ -z "$dart_bin" && -x "$repo_root/.fvm/flutter_sdk/bin/dart" ]]; then
    dart_bin="$repo_root/.fvm/flutter_sdk/bin/dart"
  fi

  AKARI_RESOLVED_FLUTTER_BIN="$flutter_bin"
  AKARI_RESOLVED_DART_BIN="$dart_bin"
}

akari_run_dev_cli() {
  local repo_root="$1"
  shift

  akari_resolve_sdk_binaries "$repo_root"
  if [[ -n "$AKARI_RESOLVED_DART_BIN" && -x "$AKARI_RESOLVED_DART_BIN" ]]; then
    # Preserve the caller's cwd: relative --theme and --report paths belong to
    # the invocation directory, while the entrypoint itself is repository-bound.
    exec "$AKARI_RESOLVED_DART_BIN" "$repo_root/packages/akari_cli/bin/akari.dart" "$@"
  fi

  cd -- "$repo_root"
  exec fvm dart run packages/akari_cli/bin/akari.dart "$@"
}

akari_is_pid_running() {
  local pid="$1" line
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1 || return 1
  if [[ -e "/proc/$pid/status" ]]; then
    while IFS= read -r line; do
      if [[ "$line" == State:* ]]; then
        [[ "$line" != $'State:\tZ'* && "$line" != $'State:\tX'* && "$line" != $'State:\tx'* ]]
        return
      fi
    done < "/proc/$pid/status" 2>/dev/null || return 1
  fi
  return 0
}

akari_stop_pid() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    return 0
  fi
  if akari_is_pid_running "$pid"; then
    kill "$pid" >/dev/null 2>&1 || true
    for _ in {1..30}; do
      if ! akari_is_pid_running "$pid"; then
        break
      fi
      sleep 0.1
    done
    if akari_is_pid_running "$pid"; then
      kill -KILL "$pid" >/dev/null 2>&1 || true
    fi
  fi
}

akari_terminate_pid() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    return 0
  fi
  akari_stop_pid "$pid"
  wait "$pid" >/dev/null 2>&1 || true
}
