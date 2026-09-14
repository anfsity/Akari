#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"
repo_root="$(mozais_repo_root)"

mozais_require_command fvm
mozais_require_command cargo
mozais_require_file "$repo_root/backend/Cargo.toml" 'backend Cargo manifest'

cd -- "$repo_root"

fvm install
fvm use stable --force
fvm flutter config --enable-linux-desktop

if [[ ! -f pubspec.yaml ]]; then
  fvm flutter create \
    --platforms=linux \
    --project-name=mozais_greeter \
    --org=dev.mozais \
    --no-pub \
    .
fi

fvm flutter pub get
cargo fetch --manifest-path "$repo_root/backend/Cargo.toml" --locked
printf '%s\n' 'Flutter toolchain ready.'
fvm flutter doctor -v
