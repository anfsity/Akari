#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"
repo_root="$(akari_repo_root)"

check_only=0
if [[ "${1:-}" == '--check' ]]; then
  check_only=1
  shift
fi

if [[ "$#" -eq 0 ]]; then
  exit 0
fi

declare -a dart_files=()
declare -a rust_files=()

for raw_path in "$@"; do
  if [[ "$raw_path" = /* ]]; then
    candidate="$raw_path"
  else
    candidate="$repo_root/$raw_path"
  fi

  [[ -f "$candidate" ]] || continue

  case "$candidate" in
    *"/.dart_tool/"*|*"/build/"*|*"/crates/target/"*)
      continue
      ;;
  esac

  case "$candidate" in
    *.g.dart)
      ;;
    *.dart)
      dart_files+=("$candidate")
      ;;
    *.rs)
      rust_files+=("$candidate")
      ;;
  esac
done

status=0

if [[ "${#dart_files[@]}" -gt 0 ]]; then
  akari_resolve_sdk_binaries "$repo_root"
  declare -a dart_cmd=()
  if [[ -n "${AKARI_RESOLVED_DART_BIN:-}" && -x "$AKARI_RESOLVED_DART_BIN" ]]; then
    dart_cmd=("$AKARI_RESOLVED_DART_BIN")
  elif command -v dart >/dev/null 2>&1; then
    dart_cmd=(dart)
  elif command -v fvm >/dev/null 2>&1; then
    dart_cmd=(fvm dart)
  else
    printf 'Missing Dart formatter binary (.fvm/flutter_sdk/bin/dart, dart, or fvm).\n' >&2
    exit 1
  fi

  if [[ "$check_only" -eq 1 ]]; then
    if ! "${dart_cmd[@]}" format --output=none --set-exit-if-changed "${dart_files[@]}"; then
      status=1
    fi
  else
    if ! "${dart_cmd[@]}" format --output=write "${dart_files[@]}"; then
      status=1
    fi
  fi
fi

if [[ "${#rust_files[@]}" -gt 0 ]]; then
  if ! command -v rustfmt >/dev/null 2>&1; then
    printf 'Missing rustfmt binary.\n' >&2
    exit 1
  fi

  edition="$(sed -nE 's/^[[:space:]]*edition[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$repo_root/crates/Cargo.toml" | head -n 1)"
  edition="${edition:-2024}"

  if [[ "$check_only" -eq 1 ]]; then
    if ! rustfmt --edition "$edition" --check "${rust_files[@]}"; then
      status=1
    fi
  else
    if ! rustfmt --edition "$edition" "${rust_files[@]}"; then
      status=1
    fi
  fi
fi

exit "$status"
