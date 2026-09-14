#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

if [[ "$#" -ne 0 ]]; then
  printf '%s\n' 'Usage: scripts/verify.sh' >&2
  exit 2
fi

"$script_dir/check-toolchain.sh"

cd -- "$repo_root/backend"
cargo fmt --all -- --check
cargo check --locked
cargo test --locked -- --test-threads=1
cargo test --locked --features mock -- --test-threads=1

cd -- "$repo_root"
fvm flutter analyze
fvm flutter test

printf '%s\n' 'Mozais verification passed.'
