#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

if ! command -v fvm >/dev/null 2>&1; then
  printf '%s\n' 'fvm is missing. Install the Arch packages listed in README.md.' >&2
  exit 1
fi

cd -- "$repo_root"

fvm install stable
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
printf '%s\n' 'Flutter toolchain ready.'
fvm flutter doctor -v
