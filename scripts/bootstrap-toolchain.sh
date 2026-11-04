#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"
repo_root="$(akari_repo_root)"

akari_require_command fvm
akari_require_command cargo
akari_require_file "$repo_root/crates/akari-backend/Cargo.toml" 'backend Cargo manifest'

cd -- "$repo_root"

fvm install
fvm use stable --force
fvm flutter config --enable-linux-desktop

(cd packages/akari_cli && fvm dart pub get)
(cd apps/greeter && fvm flutter pub get)
cargo fetch --manifest-path "$repo_root/crates/Cargo.toml" --locked
printf '%s\n' 'Flutter toolchain ready.'
fvm flutter doctor -v
