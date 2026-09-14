#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

if [[ "${MOZAIS_PRIVATE_BUS:-0}" != 1 ]]; then
  exec "$script_dir/debug-dbus.sh" "$script_dir/debug-ui.sh" "$@"
fi

if [[ ! -f "$repo_root/pubspec.yaml" ]]; then
  printf '%s\n' 'pubspec.yaml is missing; run scripts/bootstrap-toolchain.sh first.' >&2
  exit 1
fi

backend="${MOZAIS_BACKEND:-mock}"
case "$backend" in
  mock|real)
    ;;
  *)
    printf 'MOZAIS_BACKEND must be mock or real, got: %s\n' "$backend" >&2
    exit 2
    ;;
esac

cd -- "$repo_root"
exec fvm flutter run \
  -d linux \
  --dart-define="MOZAIS_BACKEND=$backend" \
  "$@"
