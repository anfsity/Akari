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
"$repo_root/scripts/generate-scenes.sh"
fvm flutter analyze
fvm flutter test

cd -- "$repo_root/packages/mozais_scene_schema"
fvm dart analyze
fvm dart test

cd -- "$repo_root/packages/mozais_scene_codegen"
fvm dart analyze
fvm dart test

cd -- "$repo_root/packages/mozais_scene_editor"
fvm flutter analyze
fvm flutter test

cd -- "$repo_root"
"$repo_root/scripts/debug-dbus.sh" fvm dart run tool/dbus_gateway_smoke.dart

printf '%s\n' 'Mozais verification passed.'
