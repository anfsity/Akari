#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

cd -- "$repo_root/packages/mozais_greeter_ui"
if [[ -n "${MOZAIS_DART_BIN:-}" ]]; then
  dart_command=("$MOZAIS_DART_BIN")
else
  dart_command=(fvm dart)
fi
"${dart_command[@]}" run build_runner build
