#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

if [[ ! -f "$repo_root/pubspec.yaml" ]]; then
  printf '%s\n' 'pubspec.yaml is missing; run scripts/bootstrap-toolchain.sh first.' >&2
  exit 1
fi

backend="${MOZAIS_BACKEND:-mock}"
cd -- "$repo_root"
exec fvm flutter run \
  -d linux \
  --dart-define="MOZAIS_BACKEND=$backend" \
  "$@"
