#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"
repo_root="$(mozais_repo_root)"

mode=mock
profile=debug

usage() {
  printf '%s\n' \
    'Usage: scripts/run-backend.sh [--mock|--real] [--release]' \
    '  --mock       Build the deterministic mock greetd transport (default).' \
    '  --real       Build the production transport using GREETD_SOCK.' \
    '  --release    Build the backend in release mode.'
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --mock)
      mode=mock
      ;;
    --real)
      mode=real
      ;;
    --release)
      profile=release
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

mozais_require_command cargo
mozais_require_file "$repo_root/backend/Cargo.toml" 'backend Cargo manifest'

build_args=(
  build
  --manifest-path "$repo_root/backend/Cargo.toml"
  --locked
)
if [[ "$mode" == mock ]]; then
  build_args+=(--features mock)
fi
if [[ "$profile" == release ]]; then
  build_args+=(--release)
fi

cd -- "$repo_root"
cargo "${build_args[@]}"

backend_binary="$repo_root/backend/target/$profile/backend"
if [[ ! -x "$backend_binary" ]]; then
  printf 'Backend binary was not produced: %s\n' "$backend_binary" >&2
  exit 1
fi

exec "$backend_binary"
