#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

if [[ "$#" -eq 0 ]]; then
  set -- "$repo_root/scripts/debug-ui.sh"
fi

exec dbus-run-session -- env \
  MOZAIS_BUS_MODE=private \
  G_MESSAGES_DEBUG=all \
  "$@"
